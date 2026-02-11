//
//  MistakeDetectionHelper.swift
//  StudyAI
//
//  Detects unarchived mistakes on current page for error analysis prompting
//

import Foundation
import os.log

class MistakeDetectionHelper {
    static let shared = MistakeDetectionHelper()

    private let localStorage = QuestionLocalStorage.shared
    private let logger = Logger(subsystem: "com.studyai", category: "MistakeDetection")

    private init() {
        logger.debug("🔍 [MistakeDetection] MistakeDetectionHelper initialized")
    }

    /// Detect unarchived mistakes from current session/page (ParsedQuestion type)
    /// Returns questions that are:
    /// 1. Incorrect (isCorrect == false)
    /// 2. NOT already archived in local storage
    func getUnarchivedMistakes(from questions: [ParsedQuestion]) -> [ParsedQuestion] {
        logger.debug("🔍 [MistakeDetection] ═══════════════════════════════════════════")
        logger.debug("🔍 [MistakeDetection] MISTAKE DETECTION (ParsedQuestion)")
        logger.debug("🔍 [MistakeDetection] ═══════════════════════════════════════════")
        logger.debug("🔍 [MistakeDetection] Starting detection for \(questions.count) questions")

        // Get all archived question IDs
        let archivedQuestionIds = Set(localStorage.getAllArchivedQuestionIds())
        logger.debug("Found \(archivedQuestionIds.count) archived question IDs in local storage")

        // Filter: incorrect AND not archived
        var mistakeCount = 0
        let mistakes = questions.filter { question in
            // Check if incorrect (not graded as CORRECT)
            // Include INCORRECT, EMPTY, and PARTIAL_CREDIT
            guard let grade = question.grade else {
                logger.debug("  Question #\(question.questionNumber ?? 0): No grade - SKIP")
                return false
            }

            guard grade != "CORRECT" else {
                logger.debug("  Question #\(question.questionNumber ?? 0): CORRECT - SKIP")
                return false
            }

            // Check if not already archived
            let isArchived = archivedQuestionIds.contains(question.id)
            if isArchived {
                logger.debug("  Question #\(question.questionNumber ?? 0): Already archived - SKIP")
            } else {
                mistakeCount += 1
                logger.debug("  ✓ Question #\(question.questionNumber ?? 0): Unarchived mistake (grade: \(grade))")
            }

            return !isArchived
        }

        logger.info("✅ Found \(mistakes.count) unarchived mistakes out of \(questions.count) total questions")
        logger.debug("═══════════════════════════════════════════")
        return mistakes
    }

    /// Detect unarchived mistakes from Pro Mode (ProgressiveQuestionWithGrade type)
    /// Returns question IDs that are:
    /// 1. Incorrect (grade.isCorrect == false)
    /// 2. NOT already archived in local storage
    func getUnarchivedMistakeIds(from questionsWithGrades: [ProgressiveQuestionWithGrade]) -> [String] {  // Changed from [Int] to [String]
        logger.debug("═══════════════════════════════════════════")
        logger.debug("MISTAKE DETECTION (ProgressiveQuestionWithGrade)")
        logger.debug("═══════════════════════════════════════════")
        logger.debug("Starting detection for \(questionsWithGrades.count) Progressive questions")

        // Get all archived question IDs
        let archivedQuestionIds = Set(localStorage.getAllArchivedQuestionIds())
        logger.debug("Found \(archivedQuestionIds.count) archived question IDs in local storage")

        var mistakeIds: [String] = []  // Changed from [Int] to [String]

        for questionWithGrade in questionsWithGrades {
            let questionId = questionWithGrade.id
            let questionNumber = questionWithGrade.question.questionNumber ?? "\(questionId)"

            // Check if already archived
            let questionIdString = String(questionId)  // No longer needed to convert, but keeping for clarity
            if archivedQuestionIds.contains(questionIdString) {
                logger.debug("  Question #\(questionNumber): Already archived - SKIP")
                continue
            }

            // Check if this is a parent question with subquestions
            if questionWithGrade.isParentQuestion {
                logger.debug("  Question #\(questionNumber): Parent question with \(questionWithGrade.subquestionGrades.count) subquestions")

                // For parent questions, check each subquestion
                var hasIncorrectSubquestion = false
                for (subquestionId, gradeResult) in questionWithGrade.subquestionGrades {
                    if !gradeResult.isCorrect {
                        logger.debug("    Subquestion '\(subquestionId)': INCORRECT (score: \(gradeResult.score))")
                        hasIncorrectSubquestion = true
                        break  // Found at least one incorrect subquestion
                    } else {
                        logger.debug("    Subquestion '\(subquestionId)': CORRECT")
                    }
                }

                if hasIncorrectSubquestion {
                    mistakeIds.append(questionId)
                    logger.debug("  ✓ Question #\(questionNumber): Added to mistakes (has incorrect subquestions)")
                } else {
                    logger.debug("  Question #\(questionNumber): All subquestions correct - SKIP")
                }
            } else {
                // Regular question - check grade
                if let grade = questionWithGrade.grade {
                    if !grade.isCorrect {
                        mistakeIds.append(questionId)
                        logger.debug("  ✓ Question #\(questionNumber): Unarchived mistake (score: \(grade.score))")
                    } else {
                        logger.debug("  Question #\(questionNumber): CORRECT (score: \(grade.score)) - SKIP")
                    }
                } else {
                    logger.debug("  Question #\(questionNumber): No grade - SKIP")
                }
            }
        }

        logger.info("✅ Found \(mistakeIds.count) unarchived mistake IDs: \(mistakeIds)")
        logger.debug("═══════════════════════════════════════════")
        return mistakeIds
    }

    /// Check if current page has unarchived mistakes (ParsedQuestion)
    func hasUnarchivedMistakes(in questions: [ParsedQuestion]) -> Bool {
        return !getUnarchivedMistakes(from: questions).isEmpty
    }

    /// Check if current page has unarchived mistakes (ProgressiveQuestionWithGrade)
    func hasUnarchivedMistakes(in questionsWithGrades: [ProgressiveQuestionWithGrade]) -> Bool {
        return !getUnarchivedMistakeIds(from: questionsWithGrades).isEmpty
    }

    /// Get count of unarchived mistakes (ParsedQuestion)
    func getUnarchivedMistakeCount(in questions: [ParsedQuestion]) -> Int {
        return getUnarchivedMistakes(from: questions).count
    }

    /// Get count of unarchived mistakes (ProgressiveQuestionWithGrade)
    func getUnarchivedMistakeCount(in questionsWithGrades: [ProgressiveQuestionWithGrade]) -> Int {
        return getUnarchivedMistakeIds(from: questionsWithGrades).count
    }
}

// MARK: - QuestionLocalStorage Extension

private extension QuestionLocalStorage {
    /// Get all archived question IDs from local storage
    func getAllArchivedQuestionIds() -> [String] {
        let allQuestions = getLocalQuestions()
        return allQuestions.compactMap { $0["id"] as? String }
    }
}
