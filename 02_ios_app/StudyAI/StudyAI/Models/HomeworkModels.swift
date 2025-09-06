//
//  HomeworkModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import Foundation

struct ParsedQuestion: Codable {
    let questionNumber: Int?
    let questionText: String
    let answerText: String
    let confidence: Float
    let hasVisualElements: Bool
    
    init(questionNumber: Int? = nil, questionText: String, answerText: String, confidence: Float = 0.8, hasVisualElements: Bool = false) {
        self.questionNumber = questionNumber
        self.questionText = questionText
        self.answerText = answerText
        self.confidence = confidence
        self.hasVisualElements = hasVisualElements
    }
    
    // Computed property for unique ID
    var id: String {
        return "\(questionNumber?.description ?? "unnumbered")_\(questionText.prefix(50).hash)"
    }
}

struct HomeworkParsingResult: Codable {
    let questions: [ParsedQuestion]
    let processingTime: Double
    let overallConfidence: Float
    let parsingMethod: String
    let rawAIResponse: String
    
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
}