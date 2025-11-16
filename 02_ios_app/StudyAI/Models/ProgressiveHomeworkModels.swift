//
//  ProgressiveHomeworkModels.swift
//  StudyAI
//
//  Data models for progressive homework grading system
//  Two-phase architecture: Parse → Grade
//

import Foundation

// MARK: - Phase 1: Parsing Models

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
struct ProgressiveQuestion: Codable, Identifiable {
    let id: Int
    let questionText: String
    let studentAnswer: String
    let hasImage: Bool
    let imageRegion: ImageRegion?
    let questionType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case hasImage = "has_image"
        case imageRegion = "image_region"
        case questionType = "question_type"
    }
}

/// Response from parse-homework-questions endpoint (Phase 1)
struct ParseHomeworkQuestionsResponse: Codable {
    let success: Bool
    let subject: String
    let subjectConfidence: Float
    let totalQuestions: Int
    let questions: [ProgressiveQuestion]
    let processingTimeMs: Int
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case subject
        case subjectConfidence = "subject_confidence"
        case totalQuestions = "total_questions"
        case questions
        case processingTimeMs = "processing_time_ms"
        case error
    }
}

// MARK: - Phase 2: Grading Models

/// Result of grading a single question
struct ProgressiveGradeResult: Codable {
    let score: Float              // 0.0-1.0
    let isCorrect: Bool           // score >= 0.9
    let feedback: String          // Max 30 words
    let confidence: Float         // 0.0-1.0

    enum CodingKeys: String, CodingKey {
        case score
        case isCorrect = "is_correct"
        case feedback
        case confidence
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
    let processingTimeMs: Int
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
struct ProgressiveQuestionWithGrade: Identifiable {
    let id: Int
    let question: ProgressiveQuestion
    var grade: ProgressiveGradeResult?
    var isGrading: Bool = false
    var gradingError: String?

    /// Whether this question is complete (graded successfully or failed)
    var isComplete: Bool {
        return grade != nil || gradingError != nil
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
        return questions.filter { $0.grade?.isCorrect == true }.count
    }

    /// Number of incorrect or partial credit questions
    var incorrectCount: Int {
        return questions.filter {
            guard let grade = $0.grade else { return false }
            return !grade.isCorrect && grade.score < 0.9
        }.count
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
