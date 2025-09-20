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

// MARK: - Mistake Review Models
struct SubjectMistakeCount: Codable, Identifiable {
    let id = UUID()
    let subject: String
    let mistakeCount: Int
    let icon: String

    enum CodingKeys: String, CodingKey {
        case subject
        case mistakeCount
        case icon
    }
}

struct MistakeQuestion: Codable, Identifiable {
    let id: String
    let subject: String
    let question: String
    let correctAnswer: String
    let studentAnswer: String
    let explanation: String
    let createdAt: Date
    let confidence: Double
    let pointsEarned: Double
    let pointsPossible: Double
    let tags: [String]
    let notes: String

    // Custom initializer for manual construction
    init(id: String, subject: String, question: String, correctAnswer: String,
         studentAnswer: String, explanation: String, createdAt: Date,
         confidence: Double, pointsEarned: Double, pointsPossible: Double,
         tags: [String], notes: String) {
        self.id = id
        self.subject = subject
        self.question = question
        self.correctAnswer = correctAnswer
        self.studentAnswer = studentAnswer
        self.explanation = explanation
        self.createdAt = createdAt
        self.confidence = confidence
        self.pointsEarned = pointsEarned
        self.pointsPossible = pointsPossible
        self.tags = tags
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, question, correctAnswer, studentAnswer, explanation
        case createdAt, confidence, pointsEarned, pointsPossible, tags, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        question = try container.decode(String.self, forKey: .question)
        correctAnswer = try container.decode(String.self, forKey: .correctAnswer)
        studentAnswer = try container.decode(String.self, forKey: .studentAnswer)
        explanation = try container.decode(String.self, forKey: .explanation)
        confidence = try container.decode(Double.self, forKey: .confidence)
        pointsEarned = try container.decode(Double.self, forKey: .pointsEarned)
        pointsPossible = try container.decode(Double.self, forKey: .pointsPossible)
        tags = try container.decode([String].self, forKey: .tags)
        notes = try container.decode(String.self, forKey: .notes)

        // Handle date parsing
        let dateString = try container.decode(String.self, forKey: .createdAt)
        let formatter = ISO8601DateFormatter()
        createdAt = formatter.date(from: dateString) ?? Date()
    }
}

struct MistakeStats: Codable {
    let totalMistakes: Int
    let subjectsWithMistakes: Int
    let mistakesLastWeek: Int
    let mistakesLastMonth: Int
}

enum MistakeTimeRange: String, CaseIterable, Identifiable {
    case lastWeek = "Last Week"
    case lastMonth = "Last Month"
    case allTime = "All Time"

    var id: String { self.rawValue }

    var apiValue: String {
        switch self {
        case .lastWeek: return "last_week"
        case .lastMonth: return "last_month"
        case .allTime: return "all_time"
        }
    }

    var icon: String {
        switch self {
        case .lastWeek: return "calendar.badge.clock"
        case .lastMonth: return "calendar"
        case .allTime: return "clock"
        }
    }
}