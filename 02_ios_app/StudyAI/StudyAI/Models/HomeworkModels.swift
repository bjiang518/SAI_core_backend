//
//  HomeworkModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import Foundation
import SwiftUI

// MARK: - Backend JSON Models (Direct Parsing)

/// Backend JSON response structure (matches improved_openai_service.py output)
struct BackendHomeworkResponse: Decodable {  // Changed from Codable to Decodable (we only decode, not encode)
    let subject: String
    let subjectConfidence: Float
    let totalQuestionsFound: Int
    let questions: [BackendQuestion]
    let performanceSummary: BackendPerformanceSummary
    let processingNotes: String?

    enum CodingKeys: String, CodingKey {
        case subject
        case subjectConfidence = "subject_confidence"
        case totalQuestionsFound = "total_questions_found"
        case questions
        case sections  // For hierarchical mode
        case performanceSummary = "performance_summary"
        case processingNotes = "processing_notes"
    }

    // Custom decoding to handle both flat (baseline) and nested (hierarchical) structures
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        subject = try container.decode(String.self, forKey: .subject)
        totalQuestionsFound = try container.decode(Int.self, forKey: .totalQuestionsFound)
        performanceSummary = try container.decode(BackendPerformanceSummary.self, forKey: .performanceSummary)
        processingNotes = try? container.decode(String.self, forKey: .processingNotes)

        // Handle subjectConfidence as Float or String
        if let floatValue = try? container.decode(Float.self, forKey: .subjectConfidence) {
            subjectConfidence = floatValue
        } else if let stringValue = try? container.decode(String.self, forKey: .subjectConfidence) {
            subjectConfidence = Float(stringValue) ?? 0.5
        } else {
            subjectConfidence = 0.5
        }

        // Handle questions: Try flat array first (baseline mode), then sections (hierarchical mode)
        if let flatQuestions = try? container.decode([BackendQuestion].self, forKey: .questions) {
            // Baseline mode: flat questions array
            questions = flatQuestions
            print("📊 Decoded flat questions array (baseline mode): \(flatQuestions.count) questions")
        } else if let sections = try? container.decode([BackendSection].self, forKey: .sections) {
            // Hierarchical mode: flatten sections into questions array
            questions = sections.flatMap { $0.questions }
            print("📊 Decoded sections (hierarchical mode): \(sections.count) sections, \(questions.count) total questions")
        } else {
            // Fallback: empty array
            questions = []
            print("⚠️ No questions or sections found, using empty array")
        }
    }
}

// Section structure for hierarchical mode
struct BackendSection: Decodable {
    let sectionId: String?
    let sectionTitle: String?
    let sectionType: String?
    let questions: [BackendQuestion]

    enum CodingKeys: String, CodingKey {
        case sectionId = "section_id"
        case sectionTitle = "section_title"
        case sectionType = "section_type"
        case questions
    }
}

struct BackendQuestion: Decodable {  // Changed from Codable to Decodable
    let questionNumber: Int?
    let rawQuestionText: String?
    let questionText: String
    let studentAnswer: String?
    let correctAnswer: String?
    let grade: String?
    let pointsEarned: Float?
    let pointsPossible: Float?
    let confidence: Float?  // Made optional - field removed from backend
    let hasVisuals: Bool?
    let feedback: String?

    // Hierarchical fields
    let isParent: Bool?
    let hasSubquestions: Bool?
    let parentContent: String?
    let subquestions: [BackendQuestion]?
    let subquestionNumber: String?
    let parentSummary: BackendParentSummary?

    enum CodingKeys: String, CodingKey {
        case questionNumber = "question_number"
        case rawQuestionText = "raw_question_text"
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case correctAnswer = "correct_answer"
        case grade
        case pointsEarned = "points_earned"
        case pointsPossible = "points_possible"
        case confidence
        case hasVisuals = "has_visuals"
        case feedback
        case isParent = "is_parent"
        case hasSubquestions = "has_subquestions"
        case parentContent = "parent_content"
        case subquestions
        case subquestionNumber = "subquestion_number"
        case parentSummary = "parent_summary"
    }

    // Custom decoding to handle question_number as Int or String (e.g., "1a", "2b")
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle questionNumber as Int or String
        if let intValue = try? container.decode(Int.self, forKey: .questionNumber) {
            questionNumber = intValue
        } else if let stringValue = try? container.decode(String.self, forKey: .questionNumber) {
            // Extract numeric part from strings like "1a", "2b"
            let numericString = stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            questionNumber = Int(numericString)
        } else {
            questionNumber = nil
        }

        rawQuestionText = try? container.decode(String.self, forKey: .rawQuestionText)
        questionText = try container.decode(String.self, forKey: .questionText)
        studentAnswer = try? container.decode(String.self, forKey: .studentAnswer)
        correctAnswer = try? container.decode(String.self, forKey: .correctAnswer)
        grade = try? container.decode(String.self, forKey: .grade)

        // Handle Float fields as Float or String
        if let floatValue = try? container.decode(Float.self, forKey: .pointsEarned) {
            pointsEarned = floatValue
        } else if let stringValue = try? container.decode(String.self, forKey: .pointsEarned) {
            pointsEarned = Float(stringValue)
        } else {
            pointsEarned = nil
        }

        if let floatValue = try? container.decode(Float.self, forKey: .pointsPossible) {
            pointsPossible = floatValue
        } else if let stringValue = try? container.decode(String.self, forKey: .pointsPossible) {
            pointsPossible = Float(stringValue)
        } else {
            pointsPossible = nil
        }

        if let floatValue = try? container.decode(Float.self, forKey: .confidence) {
            confidence = floatValue
        } else if let stringValue = try? container.decode(String.self, forKey: .confidence) {
            confidence = Float(stringValue)
        } else {
            confidence = nil  // Field removed from backend
        }

        hasVisuals = try? container.decode(Bool.self, forKey: .hasVisuals)
        feedback = try? container.decode(String.self, forKey: .feedback)
        isParent = try? container.decode(Bool.self, forKey: .isParent)
        hasSubquestions = try? container.decode(Bool.self, forKey: .hasSubquestions)
        parentContent = try? container.decode(String.self, forKey: .parentContent)
        subquestions = try? container.decode([BackendQuestion].self, forKey: .subquestions)
        subquestionNumber = try? container.decode(String.self, forKey: .subquestionNumber)
        parentSummary = try? container.decode(BackendParentSummary.self, forKey: .parentSummary)
    }
}

struct BackendParentSummary: Codable {
    let totalEarned: Float
    let totalPossible: Float
    let overallFeedback: String?

    enum CodingKeys: String, CodingKey {
        case totalEarned = "total_earned"
        case totalPossible = "total_possible"
        case overallFeedback = "overall_feedback"
    }
}

struct BackendPerformanceSummary: Decodable {  // Changed from Codable to Decodable
    let totalCorrect: Int
    let totalIncorrect: Int
    let totalEmpty: Int
    let accuracyRate: Float
    let summaryText: String

    enum CodingKeys: String, CodingKey {
        case totalCorrect = "total_correct"
        case totalIncorrect = "total_incorrect"
        case totalEmpty = "total_empty"
        case accuracyRate = "accuracy_rate"
        case summaryText = "summary_text"
    }

    // Custom decoding to handle accuracy_rate as Float or String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        totalCorrect = try container.decode(Int.self, forKey: .totalCorrect)
        totalIncorrect = try container.decode(Int.self, forKey: .totalIncorrect)
        totalEmpty = try container.decode(Int.self, forKey: .totalEmpty)
        summaryText = try container.decode(String.self, forKey: .summaryText)

        // Handle accuracyRate as Float or String
        if let floatValue = try? container.decode(Float.self, forKey: .accuracyRate) {
            accuracyRate = floatValue
        } else if let stringValue = try? container.decode(String.self, forKey: .accuracyRate) {
            accuracyRate = Float(stringValue) ?? 0.0
        } else {
            accuracyRate = 0.0
        }
    }
}

// MARK: - iOS Display Models

struct ParsedQuestion: Codable {
    let questionNumber: Int?
    let rawQuestionText: String?
    let questionText: String
    let answerText: String
    let confidence: Float?  // Made optional - field removed from backend
    let hasVisualElements: Bool

    // Grading fields (optional for backward compatibility)
    let studentAnswer: String?
    let correctAnswer: String?
    let grade: String? // CORRECT, INCORRECT, EMPTY, PARTIAL_CREDIT
    let pointsEarned: Float?
    let pointsPossible: Float?
    let feedback: String?

    // Parent/child structure (for hierarchical parsing)
    let isParent: Bool?
    let hasSubquestions: Bool?
    let parentContent: String?
    let subquestions: [ParsedQuestion]?
    let subquestionNumber: String?  // e.g., "1a", "1b"
    let parentSummary: ParentSummary?

    init(questionNumber: Int? = nil,
         rawQuestionText: String? = nil,
         questionText: String,
         answerText: String,
         confidence: Float? = nil,  // Made optional with nil default
         hasVisualElements: Bool = false,
         studentAnswer: String? = nil,
         correctAnswer: String? = nil,
         grade: String? = nil,
         pointsEarned: Float? = nil,
         pointsPossible: Float? = nil,
         feedback: String? = nil,
         isParent: Bool? = nil,
         hasSubquestions: Bool? = nil,
         parentContent: String? = nil,
         subquestions: [ParsedQuestion]? = nil,
         subquestionNumber: String? = nil,
         parentSummary: ParentSummary? = nil) {
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
        self.isParent = isParent
        self.hasSubquestions = hasSubquestions
        self.parentContent = parentContent
        self.subquestions = subquestions
        self.subquestionNumber = subquestionNumber
        self.parentSummary = parentSummary
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

struct ParentSummary: Codable {
    let totalEarned: Float
    let totalPossible: Float
    let overallFeedback: String?

    var scoreText: String {
        return "\(String(format: "%.1f", totalEarned))/\(String(format: "%.1f", totalPossible))"
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

// MARK: - JSON to iOS Model Converters

extension BackendHomeworkResponse {
    /// Convert backend JSON to iOS ParsedQuestion array
    func toParsedQuestions() -> [ParsedQuestion] {
        return questions.map { $0.toParsedQuestion() }
    }

    /// Convert backend JSON to iOS PerformanceSummary
    func toPerformanceSummary() -> PerformanceSummary {
        return PerformanceSummary(
            totalCorrect: performanceSummary.totalCorrect,
            totalIncorrect: performanceSummary.totalIncorrect,
            totalEmpty: performanceSummary.totalEmpty,
            accuracyRate: performanceSummary.accuracyRate,
            summaryText: performanceSummary.summaryText
        )
    }
}

extension BackendQuestion {
    /// Convert backend question to iOS ParsedQuestion
    func toParsedQuestion() -> ParsedQuestion {
        // Convert subquestions recursively
        let convertedSubquestions = subquestions?.map { $0.toParsedQuestion() }

        // Convert parent summary
        let convertedParentSummary = parentSummary.map { summary in
            ParentSummary(
                totalEarned: summary.totalEarned,
                totalPossible: summary.totalPossible,
                overallFeedback: summary.overallFeedback
            )
        }

        return ParsedQuestion(
            questionNumber: questionNumber,
            rawQuestionText: rawQuestionText,
            questionText: questionText,
            answerText: correctAnswer ?? studentAnswer ?? "",
            confidence: confidence,
            hasVisualElements: hasVisuals ?? false,
            studentAnswer: studentAnswer,
            correctAnswer: correctAnswer,
            grade: grade,
            pointsEarned: pointsEarned,
            pointsPossible: pointsPossible,
            feedback: feedback,
            isParent: isParent,
            hasSubquestions: hasSubquestions,
            parentContent: parentContent,
            subquestions: convertedSubquestions,
            subquestionNumber: subquestionNumber,
            parentSummary: convertedParentSummary
        )
    }
}

// MARK: - Mistake Review Models

struct SubjectMistakeCount: Codable, Identifiable {
    var id: UUID
    let subject: String
    let mistakeCount: Int
    let icon: String

    // Custom initializer for JSON decoding - generates UUID if not provided
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Generate UUID for id since it's not in JSON
        self.id = UUID()
        self.subject = try container.decode(String.self, forKey: .subject)
        self.mistakeCount = try container.decode(Int.self, forKey: .mistakeCount)
        self.icon = try container.decode(String.self, forKey: .icon)
    }

    // Regular initializer for programmatic creation
    init(id: UUID = UUID(), subject: String, mistakeCount: Int, icon: String) {
        self.id = id
        self.subject = subject
        self.mistakeCount = mistakeCount
        self.icon = icon
    }

    // Coding keys for JSON encoding/decoding (excludes id since it's generated)
    enum CodingKeys: String, CodingKey {
        case subject, mistakeCount, icon
    }
}

struct MistakeQuestion: Codable, Identifiable {
    let id: String
    let subject: String
    let question: String  // Short preview for lists
    let rawQuestionText: String  // Full original question from image
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
    init(id: String, subject: String, question: String, rawQuestionText: String? = nil, correctAnswer: String,
         studentAnswer: String, explanation: String, createdAt: Date,
         confidence: Double, pointsEarned: Double, pointsPossible: Double,
         tags: [String], notes: String) {
        self.id = id
        self.subject = subject
        self.question = question
        self.rawQuestionText = rawQuestionText ?? question  // Fallback to question if not provided
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
        case id, subject, question, rawQuestionText, correctAnswer, studentAnswer, explanation
        case createdAt, confidence, pointsEarned, pointsPossible, tags, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        question = try container.decode(String.self, forKey: .question)
        rawQuestionText = try container.decodeIfPresent(String.self, forKey: .rawQuestionText) ?? question  // Fallback to question if not available
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
        self.createdAt = formatter.date(from: dateString) ?? Date()
    }
}

struct MistakeStats: Codable {
    let totalMistakes: Int
    let subjectsWithMistakes: Int
    let mistakesLastWeek: Int
    let mistakesLastMonth: Int
}

enum MistakeTimeRange: String, CaseIterable, Identifiable {
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .thisWeek: return NSLocalizedString("mistakeReview.timeRange.thisWeek", comment: "")
        case .thisMonth: return NSLocalizedString("mistakeReview.timeRange.thisMonth", comment: "")
        case .allTime: return NSLocalizedString("mistakeReview.timeRange.allTime", comment: "")
        }
    }

    var apiValue: String {
        switch self {
        case .thisWeek: return "last_week"
        case .thisMonth: return "last_month"
        case .allTime: return "all_time"
        }
    }

    var icon: String {
        switch self {
        case .thisWeek: return "calendar.badge.clock"
        case .thisMonth: return "calendar"
        case .allTime: return "clock"
        }
    }
}