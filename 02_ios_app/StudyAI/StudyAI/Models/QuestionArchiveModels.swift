//
//  QuestionArchiveModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import Foundation

// MARK: - Grade Result Enum

enum GradeResult: String, Codable, CaseIterable {
    case correct = "CORRECT"
    case incorrect = "INCORRECT" 
    case empty = "EMPTY"
    case partialCredit = "PARTIAL_CREDIT"
    
    var displayName: String {
        switch self {
        case .correct: return "Correct"
        case .incorrect: return "Incorrect"
        case .empty: return "Empty"
        case .partialCredit: return "Partial Credit"
        }
    }
    
    var color: String {
        switch self {
        case .correct: return "green"
        case .incorrect: return "red"
        case .empty: return "gray"
        case .partialCredit: return "orange"
        }
    }
}

// MARK: - Individual Question Archive Models

struct ArchivedQuestion: Codable, Identifiable {
    let id: String
    let userId: String
    let subject: String
    let questionText: String
    let answerText: String
    let confidence: Float
    let hasVisualElements: Bool
    let originalImageUrl: String?
    let questionImageUrl: String? // Cropped image of just this question
    let processingTime: Double
    let archivedAt: Date
    let reviewCount: Int
    let lastReviewedAt: Date?
    let tags: [String]? // User-added tags
    let notes: String? // User notes for this specific question
    
    // Grading-specific fields (optional for backward compatibility)
    let studentAnswer: String? // Student's provided answer
    let grade: GradeResult? // CORRECT/INCORRECT/EMPTY
    let points: Float? // Points earned for this question
    let maxPoints: Float? // Maximum points possible
    let feedback: String? // AI-generated feedback for the student
    let isGraded: Bool // Whether this question was graded vs just answered
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        subject: String,
        questionText: String,
        answerText: String,
        confidence: Float,
        hasVisualElements: Bool,
        originalImageUrl: String? = nil,
        questionImageUrl: String? = nil,
        processingTime: Double,
        archivedAt: Date = Date(),
        reviewCount: Int = 0,
        lastReviewedAt: Date? = nil,
        tags: [String]? = nil,
        notes: String? = nil,
        studentAnswer: String? = nil,
        grade: GradeResult? = nil,
        points: Float? = nil,
        maxPoints: Float? = nil,
        feedback: String? = nil,
        isGraded: Bool = false
    ) {
        self.id = id
        self.userId = userId
        self.subject = subject
        self.questionText = questionText
        self.answerText = answerText
        self.confidence = confidence
        self.hasVisualElements = hasVisualElements
        self.originalImageUrl = originalImageUrl
        self.questionImageUrl = questionImageUrl
        self.processingTime = processingTime
        self.archivedAt = archivedAt
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.tags = tags
        self.notes = notes
        self.studentAnswer = studentAnswer
        self.grade = grade
        self.points = points
        self.maxPoints = maxPoints
        self.feedback = feedback
        self.isGraded = isGraded
    }
}

// MARK: - Question Archive Request

struct QuestionArchiveRequest {
    let questions: [ParsedQuestion]
    let selectedQuestionIndices: [Int] // Array instead of Set for ordered access
    let detectedSubject: String
    let subjectConfidence: Float
    let originalImageUrl: String?
    let processingTime: Double
    let userNotes: [String] // Notes per question in same order as selectedQuestionIndices
    let userTags: [[String]] // Tags per question in same order as selectedQuestionIndices
}

// MARK: - Enhanced Homework Parsing Result with Subject Detection

struct EnhancedHomeworkParsingResult: Codable {
    let questions: [ParsedQuestion]
    let detectedSubject: String
    let subjectConfidence: Float
    let processingTime: Double
    let overallConfidence: Float
    let parsingMethod: String
    let rawAIResponse: String
    let totalQuestionsFound: Int?
    let jsonParsingUsed: Bool?
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
    
    var isHighConfidenceSubject: Bool {
        return subjectConfidence >= 0.8
    }
    
    var isReliableParsing: Bool {
        return jsonParsingUsed == true || parsingMethod.contains("JSON")
    }
    
    var parsingQualityDescription: String {
        if isReliableParsing {
            return "High Quality (JSON Parsing)"
        } else if parsingMethod.contains("Fallback") {
            return "Good Quality (Fallback Parsing)"
        } else {
            return "Standard Quality"
        }
    }
    
    // Calculate accuracy from performance summary or questions
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

// MARK: - Question Archive Statistics

struct QuestionArchiveStatistics {
    let totalQuestions: Int
    let totalSubjects: Int
    let averageConfidence: Float
    let mostStudiedSubject: String?
    let recentlyArchivedCount: Int // Last 7 days
    let totalReviewCount: Int
    let subjectBreakdown: [String: Int]
    let confidenceDistribution: [String: Int] // High/Medium/Low confidence
}

// MARK: - Question Search and Filter Models

struct QuestionSearchFilter {
    let searchText: String?
    let subjects: [String]?
    let confidenceRange: ClosedRange<Float>?
    let dateRange: ClosedRange<Date>?
    let hasVisualElements: Bool?
    let tags: [String]?
    let minReviewCount: Int?
    
    init(
        searchText: String? = nil,
        subjects: [String]? = nil,
        confidenceRange: ClosedRange<Float>? = nil,
        dateRange: ClosedRange<Date>? = nil,
        hasVisualElements: Bool? = nil,
        tags: [String]? = nil,
        minReviewCount: Int? = nil
    ) {
        self.searchText = searchText
        self.subjects = subjects
        self.confidenceRange = confidenceRange
        self.dateRange = dateRange
        self.hasVisualElements = hasVisualElements
        self.tags = tags
        self.minReviewCount = minReviewCount
    }
}

// MARK: - Question Archive Summary for List Views

struct QuestionSummary: Codable, Identifiable {
    let id: String
    let subject: String
    let questionText: String
    let confidence: Float
    let hasVisualElements: Bool
    let archivedAt: Date
    let reviewCount: Int
    let tags: [String]?
    
    // Grading summary fields
    let grade: GradeResult?
    let points: Float?
    let maxPoints: Float?
    let isGraded: Bool
    
    // Computed property for display
    var shortQuestionText: String {
        if questionText.count > 100 {
            return String(questionText.prefix(97)) + "..."
        }
        return questionText
    }
    
    var confidenceLevel: String {
        switch confidence {
        case 0.8...1.0: return "High"
        case 0.6..<0.8: return "Medium"
        default: return "Low"
        }
    }
    
    var gradeDisplayText: String {
        guard isGraded, let grade = grade else { return "Not Graded" }
        if let points = points, let maxPoints = maxPoints {
            return "\(grade.displayName) (\(String(format: "%.1f", points))/\(String(format: "%.1f", maxPoints)))"
        }
        return grade.displayName
    }
    
    var scorePercentage: Float? {
        guard let points = points, let maxPoints = maxPoints, maxPoints > 0 else { return nil }
        return (points / maxPoints) * 100
    }
}