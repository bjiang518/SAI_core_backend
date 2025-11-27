//
//  ProgressiveHomeworkModels.swift
//  StudyAI
//
//  Data models for progressive homework grading system
//  Supports both flat and hierarchical question structures
//

import Foundation

// MARK: - Phase 1: Parsing Models

// Note: ProgressiveSubquestion is now in ProgressiveSubquestionModel.swift

/// Image region with normalized coordinates
struct ImageRegion: Codable {
    let topLeft: [Double]         // [x, y] normalized to [0-1]
    let bottomRight: [Double]     // [x, y] normalized to [0-1]
    let description: String?

    enum CodingKeys: String, CodingKey {
        case topLeft = "top_left"
        case bottomRight = "bottom_right"
        case description
    }
}

/// Individual question parsed from homework
/// Supports both flat questions and hierarchical parent questions
struct ProgressiveQuestion: Codable, Identifiable {
    let id: Int
    let questionNumber: String?

    // Hierarchical support
    let isParent: Bool?
    let hasSubquestions: Bool?
    let parentContent: String?
    let subquestions: [ProgressiveSubquestion]?

    // Regular question fields (used when isParent = false or nil)
    let questionText: String?
    let studentAnswer: String?

    // Image region (optional) - Made optional for compatibility with simplified AI response
    let hasImage: Bool?
    let imageRegion: ImageRegion?
    let questionType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionNumber = "question_number"
        case isParent = "is_parent"
        case hasSubquestions = "has_subquestions"
        case parentContent = "parent_content"
        case subquestions
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case hasImage = "has_image"
        case imageRegion = "image_region"
        case questionType = "question_type"
    }

    /// Check if this is a parent question with subquestions
    var isParentQuestion: Bool {
        return isParent == true && hasSubquestions == true
    }

    /// Get display text (parent content or question text)
    var displayText: String {
        if isParentQuestion {
            return parentContent ?? "Question \(id)"
        } else {
            return questionText ?? ""
        }
    }

    /// Get student answer (for regular questions only)
    var displayStudentAnswer: String {
        return studentAnswer ?? ""
    }
}

/// Dimensions of the image processed by backend
struct ProcessedImageDimensions: Codable {
    let width: Int
    let height: Int
}

/// Response from parse-homework-questions endpoint (Phase 1)
struct ParseHomeworkQuestionsResponse: Codable {
    let success: Bool
    let subject: String
    let subjectConfidence: Float
    let totalQuestions: Int
    let questions: [ProgressiveQuestion]
    let processingTimeMs: Int?
    let error: String?
    let processedImageDimensions: ProcessedImageDimensions?  // NEW: Backend image dimensions for coordinate scaling

    enum CodingKeys: String, CodingKey {
        case success
        case subject
        case subjectConfidence = "subject_confidence"
        case totalQuestions = "total_questions"
        case questions
        case processingTimeMs = "processing_time_ms"
        case error
        case processedImageDimensions = "processed_image_dimensions"
    }
}

// MARK: - Phase 2: Grading Models

/// Result of grading a single question or subquestion
struct ProgressiveGradeResult: Codable {
    let score: Float              // 0.0-1.0
    let isCorrect: Bool           // score >= 0.9
    let feedback: String          // Max 30 words
    let confidence: Float         // 0.0-1.0
    let correctAnswer: String?    // The expected/correct answer

    enum CodingKeys: String, CodingKey {
        case score
        case isCorrect = "is_correct"
        case feedback
        case confidence
        case correctAnswer = "correct_answer"
    }

    /// Color for UI display
    var scoreColor: ScoreColor {
        if isCorrect { return .correct }
        if score >= 0.5 { return .partial }
        return .incorrect
    }

    enum ScoreColor {
        case correct    // Green
        case partial    // Orange
        case incorrect  // Red
    }
}

/// Response from grade-question endpoint (Phase 2)
struct GradeSingleQuestionResponse: Codable {
    let success: Bool
    let grade: ProgressiveGradeResult?
    let processingTimeMs: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case grade
        case processingTimeMs = "processing_time_ms"
        case error
    }
}

// MARK: - Combined Models for ViewModel

/// Question with its grade result
/// Supports both flat questions and hierarchical parent questions
struct ProgressiveQuestionWithGrade: Identifiable {
    let id: Int
    let question: ProgressiveQuestion

    // For regular questions: single grade
    var grade: ProgressiveGradeResult?
    var isGrading: Bool = false
    var gradingError: String?

    // For parent questions: grades for each subquestion
    var subquestionGrades: [String: ProgressiveGradeResult] = [:]  // key = subquestion id
    var subquestionGradingStatus: [String: Bool] = [:]  // key = subquestion id, value = isGrading
    var subquestionErrors: [String: String] = [:]  // key = subquestion id

    // ✅ NEW: Archive status (questions remain visible after archiving)
    var isArchived: Bool = false

    /// Check if this question is a parent with subquestions
    var isParentQuestion: Bool {
        return question.isParentQuestion
    }

    /// Get total graded subquestions (for parent questions)
    var gradedSubquestionsCount: Int {
        return subquestionGrades.count
    }

    /// Get total subquestions (for parent questions)
    var totalSubquestionsCount: Int {
        return question.subquestions?.count ?? 0
    }

    /// Check if all subquestions are graded (for parent questions)
    var allSubquestionsGraded: Bool {
        guard isParentQuestion else { return grade != nil }
        return gradedSubquestionsCount == totalSubquestionsCount
    }

    /// Calculate overall score for parent question (average of subquestions)
    var parentScore: Float? {
        guard isParentQuestion, !subquestionGrades.isEmpty else { return nil }
        let totalScore = subquestionGrades.values.reduce(0.0) { $0 + $1.score }
        return totalScore / Float(subquestionGrades.count)
    }

    /// Check if parent question is correct (all subquestions correct)
    var parentIsCorrect: Bool? {
        guard isParentQuestion else { return grade?.isCorrect }
        return subquestionGrades.values.allSatisfy { $0.isCorrect }
    }

    /// Whether this question is complete (graded successfully or failed)
    var isComplete: Bool {
        if isParentQuestion {
            return allSubquestionsGraded || !subquestionErrors.isEmpty
        } else {
            return grade != nil || gradingError != nil
        }
    }
}

/// Complete homework grading state
struct HomeworkGradingState {
    var subject: String?
    var subjectConfidence: Float = 0.0
    var questions: [ProgressiveQuestionWithGrade] = []
    var croppedImages: [Int: Data] = [:]  // questionId -> JPEG data

    /// Progress: 0.0 to 1.0
    var progress: Float {
        guard !questions.isEmpty else { return 0.0 }
        let completed = questions.filter { $0.isComplete }.count
        return Float(completed) / Float(questions.count)
    }

    /// Number of correctly answered questions
    var correctCount: Int {
        var count = 0
        for q in questions {
            if q.isParentQuestion {
                // For parent questions, count as correct if ALL subquestions correct
                if q.parentIsCorrect == true {
                    count += 1
                }
            } else {
                // For regular questions
                if q.grade?.isCorrect == true {
                    count += 1
                }
            }
        }
        return count
    }

    /// Number of incorrect or partial credit questions
    var incorrectCount: Int {
        var count = 0
        for q in questions {
            if q.isParentQuestion {
                // For parent questions, count as incorrect if ANY subquestion incorrect
                if q.parentIsCorrect == false {
                    count += 1
                }
            } else {
                // For regular questions
                if let grade = q.grade, !grade.isCorrect && grade.score < 0.9 {
                    count += 1
                }
            }
        }
        return count
    }

    /// Accuracy rate: 0.0 to 1.0
    var accuracyRate: Float {
        guard !questions.isEmpty else { return 0.0 }
        return Float(correctCount) / Float(questions.count)
    }

    /// Whether all questions have been graded
    var isComplete: Bool {
        return !questions.isEmpty && questions.allSatisfy { $0.isComplete }
    }
}

// MARK: - Request Models

/// Request to parse homework (Phase 1)
struct ParseHomeworkRequest: Codable {
    let base64Image: String
    let parsingMode: String  // "standard" or "detailed"

    enum CodingKeys: String, CodingKey {
        case base64Image = "base64_image"
        case parsingMode = "parsing_mode"
    }
}

/// Request to grade single question (Phase 2)
struct GradeQuestionRequest: Codable {
    let questionText: String
    let studentAnswer: String
    let correctAnswer: String?
    let subject: String?
    let contextImageBase64: String?

    enum CodingKeys: String, CodingKey {
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case correctAnswer = "correct_answer"
        case subject
        case contextImageBase64 = "context_image_base64"
    }
}

// MARK: - Error Types

enum ProgressiveGradingError: LocalizedError {
    case parsingFailed(String)
    case gradingFailed(String)
    case imageCropFailed(Int)  // questionId
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .gradingFailed(let message):
            return "Grading failed: \(message)"
        case .imageCropFailed(let questionId):
            return "Failed to crop image for question \(questionId)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
