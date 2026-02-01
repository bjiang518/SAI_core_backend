//
//  HomeworkModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/3/25.
//

import Foundation

// MARK: - Application Constants

struct AppConstants {
    // Storage limits
    static let maxLocalQuestions = 100
    static let maxPracticeQuestions = 40
    static let maxSelectedMistakes = 20
    static let practiceQuestionsMultiplier = 2

    // Data retention
    static let dataRetentionDays = 90
    static let weaknessMigrationDays = 21

    // Timeout & retry
    static let apiTimeoutSeconds = 60.0
    static let circuitBreakerThreshold = 5
    static let circuitBreakerResetSeconds = 60.0

    // Cache settings
    static let dateCacheSizeLimit = 200
}

// MARK: - Error Analysis Status

enum ErrorAnalysisStatus: String, Codable {
    case pending
    case processing
    case completed
    case failed

    var displayText: String {
        switch self {
        case .pending: return "Queued for analysis"
        case .processing: return "Analyzing..."
        case .completed: return "Analysis complete"
        case .failed: return "Analysis unavailable"
        }
    }

    var icon: String {
        switch self {
        case .pending, .processing: return "hourglass"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }
}

// MARK: - Hierarchical Taxonomy Enums

/// Math curriculum base branches (Chapter-level)
enum MathBaseBranch: String, CaseIterable {
    case numberOperations = "Number & Operations"
    case algebraFoundations = "Algebra - Foundations"
    case algebraAdvanced = "Algebra - Advanced"
    case geometryFoundations = "Geometry - Foundations"
    case geometryFormal = "Geometry - Formal"
    case trigonometry = "Trigonometry"
    case statistics = "Statistics"
    case probability = "Probability"
    case calculusDifferential = "Calculus - Differential"
    case calculusIntegral = "Calculus - Integral"
    case discreteMath = "Discrete Mathematics"
    case mathModeling = "Mathematical Modeling & Applications"
}

/// Simplified error types (3 types instead of 9)
enum ErrorSeverityType: String, Codable {
    case executionError = "execution_error"
    case conceptualGap = "conceptual_gap"
    case needsRefinement = "needs_refinement"

    var displayName: String {
        switch self {
        case .executionError: return "Execution Error"
        case .conceptualGap: return "Concept Gap"
        case .needsRefinement: return "Needs Refinement"
        }
    }

    var description: String {
        switch self {
        case .executionError:
            return "Student understands concept but made careless mistake"
        case .conceptualGap:
            return "Student has fundamental misunderstanding"
        case .needsRefinement:
            return "Answer is correct but could be improved"
        }
    }

    var icon: String {
        switch self {
        case .executionError: return "exclamationmark.circle"
        case .conceptualGap: return "brain.head.profile"
        case .needsRefinement: return "star.circle"
        }
    }

    var color: String {
        switch self {
        case .executionError: return "yellow"
        case .conceptualGap: return "red"
        case .needsRefinement: return "blue"
        }
    }

    var severity: String {
        switch self {
        case .executionError: return "low"
        case .conceptualGap: return "high"
        case .needsRefinement: return "minimal"
        }
    }
}

import SwiftUI

// MARK: - String Extension for Unicode Decoding

extension String {
    /// Decode Unicode escape sequences from backend JSON
    ///
    /// Supports common symbols in homework:
    /// - Math: ° (degree), ± (plus-minus), × (multiply), ÷ (divide), √ (square root), π, ∞
    /// - Comparison: ≤ ≥ ≠ ≈
    /// - Greek letters: α β γ δ ε θ λ μ σ φ ω
    /// - Superscripts: ¹ ² ³ ⁴ ⁵ ⁶ ⁷ ⁸ ⁹ ⁰
    /// - Subscripts: ₁ ₂ ₃ ₄ ₅ ₆ ₇ ₈ ₉ ₀
    /// - Fractions: ½ ¼ ¾ ⅓ ⅔
    /// - Arrows: → ← ↑ ↓
    /// - Other: • (bullet), ✓ (checkmark)
    ///
    /// Handles formats:
    /// - \uXXXX (4 hex digits, standard Unicode)
    /// - \U00XXXXXX (8 hex digits with leading zeros, Python format)
    func decodingUnicodeEscapes() -> String {
        var result = self

        // Handle \UXXXXXXXX format (8 hex digits, Python format)
        // Example: "40\U000000b0F" -> "40°F"
        let pattern8 = "\\\\U([0-9A-Fa-f]{8})"
        if let regex8 = try? NSRegularExpression(pattern: pattern8, options: []) {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex8.matches(in: result, options: [], range: nsRange)

            for match in matches.reversed() {
                if match.numberOfRanges > 1,
                   let hexRange = Range(match.range(at: 1), in: result),
                   let fullRange = Range(match.range(at: 0), in: result) {
                    let hexString = String(result[hexRange])
                    if let codePoint = UInt32(hexString, radix: 16),
                       let scalar = Unicode.Scalar(codePoint) {
                        result.replaceSubrange(fullRange, with: String(scalar))
                    }
                }
            }
        }

        // Handle \U00XX format (uppercase U with 4 hex digits)
        // Example: "40\U00b0F" -> "40°F"
        let pattern4U = "\\\\U([0-9A-Fa-f]{4})"
        if let regex4U = try? NSRegularExpression(pattern: pattern4U, options: []) {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex4U.matches(in: result, options: [], range: nsRange)

            for match in matches.reversed() {
                if match.numberOfRanges > 1,
                   let hexRange = Range(match.range(at: 1), in: result),
                   let fullRange = Range(match.range(at: 0), in: result) {
                    let hexString = String(result[hexRange])
                    if let codePoint = UInt32(hexString, radix: 16),
                       let scalar = Unicode.Scalar(codePoint) {
                        result.replaceSubrange(fullRange, with: String(scalar))
                    }
                }
            }
        }

        // Handle standard \uXXXX format (4 hex digits)
        // Example: "π\u03c0" -> "ππ"
        let pattern4u = "\\\\u([0-9A-Fa-f]{4})"
        if let regex4u = try? NSRegularExpression(pattern: pattern4u, options: []) {
            let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex4u.matches(in: result, options: [], range: nsRange)

            for match in matches.reversed() {
                if match.numberOfRanges > 1,
                   let hexRange = Range(match.range(at: 1), in: result),
                   let fullRange = Range(match.range(at: 0), in: result) {
                    let hexString = String(result[hexRange])
                    if let codePoint = UInt32(hexString, radix: 16),
                       let scalar = Unicode.Scalar(codePoint) {
                        result.replaceSubrange(fullRange, with: String(scalar))
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Question Type Enum

/// Question type classification for different rendering styles
enum QuestionType: String, Codable {
    case multipleChoice = "multiple_choice"
    case trueFalse = "true_false"
    case fillInBlank = "fill_blank"
    case shortAnswer = "short_answer"
    case longAnswer = "long_answer"
    case calculation = "calculation"
    case matching = "matching"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .multipleChoice: return "Multiple Choice"
        case .trueFalse: return "True/False"
        case .fillInBlank: return "Fill in the Blank"
        case .shortAnswer: return "Short Answer"
        case .longAnswer: return "Long Answer"
        case .calculation: return "Calculation"
        case .matching: return "Matching"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .multipleChoice: return "list.bullet.circle"
        case .trueFalse: return "checkmark.circle.badge.xmark"
        case .fillInBlank: return "line.horizontal.3.decrease"
        case .shortAnswer: return "text.cursor"
        case .longAnswer: return "doc.text"
        case .calculation: return "number.circle"
        case .matching: return "arrow.left.arrow.right"
        case .unknown: return "questionmark.circle"
        }
    }

    var needsOptions: Bool {
        return self == .multipleChoice || self == .trueFalse
    }
}

// MARK: - Backend JSON Models (Direct Parsing)

/// Handwriting quality evaluation for Pro Mode
struct HandwritingEvaluation: Codable {
    let hasHandwriting: Bool
    let score: Float?
    let feedback: String?

    enum CodingKeys: String, CodingKey {
        case hasHandwriting = "has_handwriting"
        case score
        case feedback
    }
}

/// Backend JSON response structure (matches improved_openai_service.py output)
struct BackendHomeworkResponse: Decodable {  // Changed from Codable to Decodable (we only decode, not encode)
    let subject: String
    let subjectConfidence: Float
    let totalQuestionsFound: Int
    let questions: [BackendQuestion]
    let performanceSummary: BackendPerformanceSummary
    let handwritingEvaluation: HandwritingEvaluation?
    let processingNotes: String?

    enum CodingKeys: String, CodingKey {
        case subject
        case subjectConfidence = "subject_confidence"
        case totalQuestionsFound = "total_questions_found"
        case questions
        case sections  // For hierarchical mode
        case performanceSummary = "performance_summary"
        case handwritingEvaluation = "handwriting_evaluation"
        case processingNotes = "processing_notes"
    }

    // Custom decoding to handle both flat (baseline) and nested (hierarchical) structures
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        subject = try container.decode(String.self, forKey: .subject)
        totalQuestionsFound = try container.decode(Int.self, forKey: .totalQuestionsFound)
        performanceSummary = try container.decode(BackendPerformanceSummary.self, forKey: .performanceSummary)
        handwritingEvaluation = try? container.decode(HandwritingEvaluation.self, forKey: .handwritingEvaluation)
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
    let questionText: String?  // Made optional - parent questions only have parent_content
    let studentAnswer: String?
    let correctAnswer: String?
    let grade: String?
    let pointsEarned: Float?
    let pointsPossible: Float?
    let confidence: Float?  // Made optional - field removed from backend
    let hasVisuals: Bool?
    let feedback: String?

    // Question type fields (for type-specific rendering)
    let questionType: String?  // "multiple_choice", "true_false", "fill_blank", etc.
    let options: [String]?     // For multiple choice: ["A) Option 1", "B) Option 2", ...]

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
        case questionType = "question_type"
        case options
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

        // Decode and process Unicode escape sequences in all text fields
        if let rawText = try? container.decode(String.self, forKey: .rawQuestionText) {
            rawQuestionText = rawText.decodingUnicodeEscapes()
        } else {
            rawQuestionText = nil
        }

        // Decode parentContent first (for parent questions)
        if let parentContentRaw = try? container.decode(String.self, forKey: .parentContent) {
            parentContent = parentContentRaw.decodingUnicodeEscapes()
        } else {
            parentContent = nil
        }

        // Decode questionText (may be nil for parent questions that only have parent_content)
        if let qText = try? container.decode(String.self, forKey: .questionText) {
            questionText = qText.decodingUnicodeEscapes()
        } else {
            // Fallback: use parentContent if available, otherwise nil
            questionText = parentContent
        }

        if let studentAnswerRaw = try? container.decode(String.self, forKey: .studentAnswer) {
            studentAnswer = studentAnswerRaw.decodingUnicodeEscapes()
        } else {
            studentAnswer = nil
        }

        if let correctAnswerRaw = try? container.decode(String.self, forKey: .correctAnswer) {
            correctAnswer = correctAnswerRaw.decodingUnicodeEscapes()
        } else {
            correctAnswer = nil
        }

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

        // Handle hasVisuals as Bool or Int
        if let boolValue = try? container.decode(Bool.self, forKey: .hasVisuals) {
            hasVisuals = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .hasVisuals) {
            hasVisuals = intValue != 0
        } else {
            hasVisuals = nil
        }

        // Decode feedback with Unicode support
        if let feedbackRaw = try? container.decode(String.self, forKey: .feedback) {
            feedback = feedbackRaw.decodingUnicodeEscapes()
        } else {
            feedback = nil
        }

        questionType = try? container.decode(String.self, forKey: .questionType)

        // Decode options array with Unicode support
        if let optionsRaw = try? container.decode([String].self, forKey: .options) {
            options = optionsRaw.map { $0.decodingUnicodeEscapes() }
        } else {
            options = nil
        }

        // Handle isParent as Bool or Int
        if let boolValue = try? container.decode(Bool.self, forKey: .isParent) {
            isParent = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .isParent) {
            isParent = intValue != 0
        } else {
            isParent = nil
        }

        // Handle hasSubquestions as Bool or Int
        if let boolValue = try? container.decode(Bool.self, forKey: .hasSubquestions) {
            hasSubquestions = boolValue
        } else if let intValue = try? container.decode(Int.self, forKey: .hasSubquestions) {
            hasSubquestions = intValue != 0
        } else {
            hasSubquestions = nil
        }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalEarned = try container.decode(Float.self, forKey: .totalEarned)
        totalPossible = try container.decode(Float.self, forKey: .totalPossible)

        // Decode overallFeedback with Unicode support
        if let feedbackRaw = try? container.decode(String.self, forKey: .overallFeedback) {
            overallFeedback = feedbackRaw.decodingUnicodeEscapes()
        } else {
            overallFeedback = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(totalEarned, forKey: .totalEarned)
        try container.encode(totalPossible, forKey: .totalPossible)
        try container.encodeIfPresent(overallFeedback, forKey: .overallFeedback)
    }
}

struct BackendPerformanceSummary: Decodable {  // Changed from Codable to Decodable
    let totalCorrect: Int
    let totalIncorrect: Int
    let totalEmpty: Int
    let totalPartialCredit: Int
    let accuracyRate: Float
    let summaryText: String

    enum CodingKeys: String, CodingKey {
        case totalCorrect = "total_correct"
        case totalIncorrect = "total_incorrect"
        case totalEmpty = "total_empty"
        case totalPartialCredit = "total_partial_credit"
        case accuracyRate = "accuracy_rate"
        case summaryText = "summary_text"
    }

    // Custom decoding to handle accuracy_rate as Float or String
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        totalCorrect = try container.decode(Int.self, forKey: .totalCorrect)
        totalIncorrect = try container.decode(Int.self, forKey: .totalIncorrect)
        totalEmpty = try container.decode(Int.self, forKey: .totalEmpty)
        totalPartialCredit = (try? container.decode(Int.self, forKey: .totalPartialCredit)) ?? 0

        // Decode summaryText with Unicode support
        let summaryRaw = try container.decode(String.self, forKey: .summaryText)
        summaryText = summaryRaw.decodingUnicodeEscapes()

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

    // Question type fields (for type-specific rendering)
    let questionType: String?      // "multiple_choice", "true_false", etc.
    let options: [String]?         // Multiple choice options

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
         questionType: String? = nil,
         options: [String]? = nil,
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
        self.questionType = questionType
        self.options = options
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

    // Computed property for typed question type
    var detectedQuestionType: QuestionType {
        guard let typeString = questionType else {
            return .unknown
        }
        return QuestionType(rawValue: typeString) ?? .unknown
    }

    // Computed property to check if question has valid options
    var hasOptions: Bool {
        guard let opts = options else { return false }
        return !opts.isEmpty
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
    let totalPartialCredit: Int
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
            totalPartialCredit: performanceSummary.totalPartialCredit,
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

        // Handle questionText: use parentContent as fallback for parent questions
        let displayQuestionText = questionText ?? parentContent ?? "Parent Question"

        return ParsedQuestion(
            questionNumber: questionNumber,
            rawQuestionText: rawQuestionText,
            questionText: displayQuestionText,
            answerText: correctAnswer ?? studentAnswer ?? "",
            confidence: confidence,
            hasVisualElements: hasVisuals ?? false,
            studentAnswer: studentAnswer,
            correctAnswer: correctAnswer,
            grade: grade,
            pointsEarned: pointsEarned,
            pointsPossible: pointsPossible,
            feedback: feedback,
            questionType: questionType,
            options: options,
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

    // ✅ Error analysis fields (standardized naming)
    let errorType: String?
    let errorEvidence: String?
    let errorConfidence: Double?
    let learningSuggestion: String?
    let errorAnalysisStatus: ErrorAnalysisStatus  // ✅ Now using enum

    // ✅ Weakness tracking fields (hierarchical taxonomy)
    let weaknessKey: String?
    let baseBranch: String?           // Chapter-level taxonomy (e.g., "Algebra - Foundations")
    let detailedBranch: String?       // Topic-level taxonomy (e.g., "Linear Equations - One Variable")
    let specificIssue: String?        // AI-generated issue description

    // ✅ Pro Mode image field (for questions with images)
    let questionImageUrl: String?

    // Computed properties
    var hasErrorAnalysis: Bool {
        errorAnalysisStatus == .completed && errorType != nil
    }

    var isAnalyzing: Bool {
        errorAnalysisStatus == .pending || errorAnalysisStatus == .processing
    }

    // Custom initializer for manual construction
    init(id: String, subject: String, question: String, rawQuestionText: String? = nil, correctAnswer: String,
         studentAnswer: String, explanation: String, createdAt: Date,
         confidence: Double, pointsEarned: Double, pointsPossible: Double,
         tags: [String], notes: String,
         errorType: String? = nil, errorEvidence: String? = nil, errorConfidence: Double? = nil,
         learningSuggestion: String? = nil, errorAnalysisStatus: ErrorAnalysisStatus = .failed,
         weaknessKey: String? = nil,
         baseBranch: String? = nil, detailedBranch: String? = nil, specificIssue: String? = nil,
         questionImageUrl: String? = nil) {
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
        self.errorType = errorType
        self.errorEvidence = errorEvidence
        self.errorConfidence = errorConfidence
        self.learningSuggestion = learningSuggestion
        self.errorAnalysisStatus = errorAnalysisStatus
        self.weaknessKey = weaknessKey
        // Hierarchical taxonomy fields
        self.baseBranch = baseBranch
        self.detailedBranch = detailedBranch
        self.specificIssue = specificIssue
        self.questionImageUrl = questionImageUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, subject, question, rawQuestionText, correctAnswer, studentAnswer, explanation
        case createdAt, confidence, pointsEarned, pointsPossible, tags, notes
        case errorType, errorEvidence, errorConfidence, learningSuggestion, errorAnalysisStatus
        case weaknessKey
        case baseBranch, detailedBranch, specificIssue
        case questionImageUrl
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)

        // Decode text fields with Unicode support
        let questionRaw = try container.decode(String.self, forKey: .question)
        question = questionRaw.decodingUnicodeEscapes()

        let rawQuestionRaw = try container.decodeIfPresent(String.self, forKey: .rawQuestionText) ?? questionRaw
        rawQuestionText = rawQuestionRaw.decodingUnicodeEscapes()

        let correctAnswerRaw = try container.decode(String.self, forKey: .correctAnswer)
        correctAnswer = correctAnswerRaw.decodingUnicodeEscapes()

        let studentAnswerRaw = try container.decode(String.self, forKey: .studentAnswer)
        studentAnswer = studentAnswerRaw.decodingUnicodeEscapes()

        let explanationRaw = try container.decode(String.self, forKey: .explanation)
        explanation = explanationRaw.decodingUnicodeEscapes()

        let notesRaw = try container.decode(String.self, forKey: .notes)
        notes = notesRaw.decodingUnicodeEscapes()

        confidence = try container.decode(Double.self, forKey: .confidence)
        pointsEarned = try container.decode(Double.self, forKey: .pointsEarned)
        pointsPossible = try container.decode(Double.self, forKey: .pointsPossible)
        tags = try container.decode([String].self, forKey: .tags)

        // ✅ Decode error analysis fields (with backwards compatibility)
        errorType = try container.decodeIfPresent(String.self, forKey: .errorType)
        errorEvidence = try container.decodeIfPresent(String.self, forKey: .errorEvidence)
        errorConfidence = try container.decodeIfPresent(Double.self, forKey: .errorConfidence)
        learningSuggestion = try container.decodeIfPresent(String.self, forKey: .learningSuggestion)

        // Decode status with backwards compatibility (string → enum)
        // For old mistakes without analysis, default to failed (no analysis available)
        if let statusEnum = try? container.decodeIfPresent(ErrorAnalysisStatus.self, forKey: .errorAnalysisStatus) {
            errorAnalysisStatus = statusEnum
        } else if let statusString = try? container.decodeIfPresent(String.self, forKey: .errorAnalysisStatus) {
            errorAnalysisStatus = ErrorAnalysisStatus(rawValue: statusString) ?? .failed
        } else {
            errorAnalysisStatus = .failed
        }

        weaknessKey = try container.decodeIfPresent(String.self, forKey: .weaknessKey)

        // Decode hierarchical taxonomy fields
        baseBranch = try container.decodeIfPresent(String.self, forKey: .baseBranch)
        detailedBranch = try container.decodeIfPresent(String.self, forKey: .detailedBranch)
        specificIssue = try container.decodeIfPresent(String.self, forKey: .specificIssue)

        questionImageUrl = try container.decodeIfPresent(String.self, forKey: .questionImageUrl)

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