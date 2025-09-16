//
//  HomeworkModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import Foundation
import SwiftUI

struct ParsedQuestion: Codable {
    let questionNumber: Int?
    let rawQuestionText: String?
    let questionText: String
    let answerText: String
    let confidence: Float
    let hasVisualElements: Bool
    
    // Grading fields (optional for backward compatibility)
    let studentAnswer: String?
    let correctAnswer: String?
    let grade: String? // CORRECT, INCORRECT, EMPTY, PARTIAL_CREDIT
    let pointsEarned: Float?
    let pointsPossible: Float?
    let feedback: String?
    
    init(questionNumber: Int? = nil, 
         rawQuestionText: String? = nil,
         questionText: String, 
         answerText: String, 
         confidence: Float = 0.8, 
         hasVisualElements: Bool = false,
         studentAnswer: String? = nil,
         correctAnswer: String? = nil,
         grade: String? = nil,
         pointsEarned: Float? = nil,
         pointsPossible: Float? = nil,
         feedback: String? = nil) {
        self.questionNumber = questionNumber
        self.rawQuestionText = rawQuestionText
        self.questionText = questionText
        self.answerText = answerText
        self.confidence = confidence
        self.hasVisualElements = hasVisualElements
        self.studentAnswer = studentAnswer
        self.correctAnswer = correctAnswer
        self.grade = grade
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.feedback = feedback
    }
    
    // Computed property for unique ID
    var id: String {
        return "\(questionNumber?.description ?? "unnumbered")_\(questionText.prefix(50).hash)"
    }
    
    // Computed properties for grading display
    var isGraded: Bool {
        return grade != nil && !grade!.isEmpty
    }
    
    var gradeIcon: String {
        guard let grade = grade else { return "questionmark.circle" }
        switch grade {
        case "CORRECT": return "checkmark.circle.fill"
        case "INCORRECT": return "xmark.circle.fill"
        case "EMPTY": return "minus.circle.fill"
        case "PARTIAL_CREDIT": return "checkmark.circle"
        default: return "questionmark.circle"
        }
    }
    
    var gradeColor: Color {
        guard let grade = grade else { return .gray }
        switch grade {
        case "CORRECT": return .green
        case "INCORRECT": return .red
        case "EMPTY": return .gray
        case "PARTIAL_CREDIT": return .orange
        default: return .gray
        }
    }
    
    var scoreText: String {
        guard let earned = pointsEarned, let possible = pointsPossible else { return "" }
        return "\(String(format: "%.1f", earned))/\(String(format: "%.1f", possible))"
    }
}

struct PerformanceSummary: Codable {
    let totalCorrect: Int
    let totalIncorrect: Int
    let totalEmpty: Int
    let accuracyRate: Float
    let summaryText: String
    
    var accuracyPercentage: String {
        return String(format: "%.0f%%", accuracyRate * 100)
    }
}

struct HomeworkParsingResult: Codable {
    let questions: [ParsedQuestion]
    let processingTime: Double
    let overallConfidence: Float
    let parsingMethod: String
    let rawAIResponse: String
    let performanceSummary: PerformanceSummary?
    
    // Computed properties for easy access
    var questionCount: Int {
        return questions.count
    }
    
    var numberedQuestions: [ParsedQuestion] {
        return questions.filter { $0.questionNumber != nil }
    }
    
    var unnumberedQuestions: [ParsedQuestion] {
        return questions.filter { $0.questionNumber == nil }
    }
    
    var allQuestions: [ParsedQuestion] {
        return numberedQuestions + unnumberedQuestions
    }
    
    // Calculate accuracy from graded questions if performance summary not available
    var calculatedAccuracy: Float {
        if let summary = performanceSummary {
            return summary.accuracyRate
        }
        
        let gradedQuestions = questions.filter { $0.grade != nil }
        if gradedQuestions.isEmpty { return overallConfidence }
        
        let correctCount = gradedQuestions.filter { $0.grade == "CORRECT" }.count
        return Float(correctCount) / Float(gradedQuestions.count)
    }
}