//
//  AnswerMatchingService.swift
//  StudyAI
//
//  Created by Claude Code on 2026-02-02.
//  Optimizes practice question grading by performing client-side matching
//  before sending to expensive AI grading.
//

import Foundation

/// Client-side answer matching service to avoid unnecessary API calls
/// Handles exact matching for multiple choice, true/false, and simple answers
class AnswerMatchingService {
    static let shared = AnswerMatchingService()

    private init() {}

    /// Result of answer matching with confidence score
    struct MatchResult {
        let matchScore: Double // 0.0 to 1.0
        let isExactMatch: Bool
        let shouldSkipAIGrading: Bool // true if score >= 0.9
        let normalizedUserAnswer: String
        let normalizedCorrectAnswer: String

        var isCorrect: Bool {
            matchScore >= 0.9
        }
    }

    // MARK: - Main Matching Function

    /// Match student answer against correct answer with type-specific logic
    /// - Parameters:
    ///   - userAnswer: Student's submitted answer
    ///   - correctAnswer: The correct answer from question generation
    ///   - questionType: Type of question (multiple_choice, true_false, etc.)
    ///   - options: Multiple choice options (if applicable)
    /// - Returns: MatchResult with score and grading recommendation
    func matchAnswer(
        userAnswer: String,
        correctAnswer: String,
        questionType: String,
        options: [String: String]? = nil
    ) -> MatchResult {

        // Normalize both answers for comparison
        let normalizedUser = normalizeAnswer(userAnswer)
        let normalizedCorrect = normalizeAnswer(correctAnswer)

        #if DEBUG
        print("🔍 [AnswerMatching] Type: \(questionType)")
        print("   User: '\(userAnswer)' → '\(normalizedUser)'")
        print("   Correct: '\(correctAnswer)' → '\(normalizedCorrect)'")
        #endif

        // Route to type-specific matching
        let score: Double
        let isExact: Bool

        switch questionType.lowercased() {
        case "multiple_choice":
            (score, isExact) = matchMultipleChoice(normalizedUser, normalizedCorrect, options)

        case "true_false":
            (score, isExact) = matchTrueFalse(normalizedUser, normalizedCorrect)

        case "fill_in_the_blank", "short_answer":
            (score, isExact) = matchShortAnswer(normalizedUser, normalizedCorrect)

        case "calculation", "numeric":
            (score, isExact) = matchNumeric(normalizedUser, normalizedCorrect)

        default:
            // Unknown type: conservative matching
            (score, isExact) = matchGeneric(normalizedUser, normalizedCorrect)
        }

        let shouldSkip = score >= 0.9

        #if DEBUG
        print("   Score: \(String(format: "%.2f", score * 100))%")
        print("   Exact: \(isExact)")
        print("   Decision: \(shouldSkip ? "✅ SKIP AI (instant grade)" : "🤖 SEND TO AI")")
        #endif

        return MatchResult(
            matchScore: score,
            isExactMatch: isExact,
            shouldSkipAIGrading: shouldSkip,
            normalizedUserAnswer: normalizedUser,
            normalizedCorrectAnswer: normalizedCorrect
        )
    }

    // MARK: - Type-Specific Matching

    /// Match multiple choice answers (A, B, C, D)
    private func matchMultipleChoice(
        _ userAnswer: String,
        _ correctAnswer: String,
        _ options: [String: String]?
    ) -> (score: Double, isExact: Bool) {

        // Extract option letter (A, B, C, D)
        let userOption = extractOptionLetter(userAnswer)
        let correctOption = extractOptionLetter(correctAnswer)

        #if DEBUG
        print("   MC: User option '\(userOption)' vs Correct '\(correctOption)'")
        #endif

        // Exact match on option letter
        if userOption == correctOption && !userOption.isEmpty {
            return (1.0, true)
        }

        // Try matching against option text if available
        if let opts = options {
            // Check if user typed the full option text instead of letter
            for (letter, text) in opts {
                let normalizedText = normalizeAnswer(text)
                if normalizedText == userAnswer && letter == correctOption {
                    return (1.0, true)
                }
            }
        }

        // No match
        return (0.0, false)
    }

    /// Match true/false questions
    private func matchTrueFalse(
        _ userAnswer: String,
        _ correctAnswer: String
    ) -> (score: Double, isExact: Bool) {

        let userBool = parseBooleanAnswer(userAnswer)
        let correctBool = parseBooleanAnswer(correctAnswer)

        #if DEBUG
        print("   T/F: User \(userBool?.description ?? "nil") vs Correct \(correctBool?.description ?? "nil")")
        #endif

        guard let user = userBool, let correct = correctBool else {
            return (0.0, false)
        }

        return user == correct ? (1.0, true) : (0.0, false)
    }

    /// Match short answer questions (exact or very close)
    private func matchShortAnswer(
        _ userAnswer: String,
        _ correctAnswer: String
    ) -> (score: Double, isExact: Bool) {

        // Exact match after normalization
        if userAnswer == correctAnswer {
            return (1.0, true)
        }

        // Check if answers are very similar (90%+ character overlap)
        let similarity = calculateStringSimilarity(userAnswer, correctAnswer)

        #if DEBUG
        print("   Short Answer Similarity: \(String(format: "%.2f", similarity * 100))%")
        #endif

        // If 95%+ similar, consider it a match (typos allowed)
        if similarity >= 0.95 {
            return (1.0, false)
        }

        // 90-95% similar: borderline (curve to 100% for instant grading)
        if similarity >= 0.90 {
            return (0.95, false)
        }

        // Less than 90%: needs AI grading
        return (similarity, false)
    }

    /// Match numeric/calculation answers
    private func matchNumeric(
        _ userAnswer: String,
        _ correctAnswer: String
    ) -> (score: Double, isExact: Bool) {

        // Try to parse as numbers
        if let userNum = parseNumber(userAnswer),
           let correctNum = parseNumber(correctAnswer) {

            // Allow small rounding errors (0.01% tolerance)
            let tolerance = abs(correctNum) * 0.0001
            let difference = abs(userNum - correctNum)

            #if DEBUG
            print("   Numeric: User \(userNum) vs Correct \(correctNum)")
            print("   Difference: \(difference), Tolerance: \(tolerance)")
            #endif

            if difference <= tolerance {
                return (1.0, true)
            }

            // Calculate proximity score (within 10% = 0.5 score minimum)
            let relativeError = difference / abs(correctNum)
            let score = max(0.0, 1.0 - relativeError)

            return (score, false)
        }

        // Not numeric, fallback to string matching
        return matchGeneric(userAnswer, correctAnswer)
    }

    /// Generic string matching for unknown types
    private func matchGeneric(
        _ userAnswer: String,
        _ correctAnswer: String
    ) -> (score: Double, isExact: Bool) {

        if userAnswer == correctAnswer {
            return (1.0, true)
        }

        let similarity = calculateStringSimilarity(userAnswer, correctAnswer)
        return (similarity, false)
    }

    // MARK: - Utility Functions

    /// Normalize answer for comparison (lowercase, trim, remove punctuation)
    private func normalizeAnswer(_ answer: String) -> String {
        return answer
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[.,!?;:]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Extract option letter from multiple choice answer (A, B, C, D)
    private func extractOptionLetter(_ answer: String) -> String {
        // Match patterns like "A", "A)", "A.", "(A)", "Option A", etc.
        let pattern = #"[(\[]?([A-Da-d])[)\].]?"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: answer, range: NSRange(answer.startIndex..., in: answer)),
           let range = Range(match.range(at: 1), in: answer) {
            return String(answer[range]).uppercased()
        }

        // If no pattern match, check if entire answer is just a letter
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 1 && "ABCD".contains(trimmed) {
            return trimmed
        }

        return ""
    }

    /// Parse boolean answer from various formats
    private func parseBooleanAnswer(_ answer: String) -> Bool? {
        let lower = answer.lowercased()

        // True variants
        if ["true", "t", "yes", "y", "correct", "right", "1"].contains(lower) {
            return true
        }

        // False variants
        if ["false", "f", "no", "n", "incorrect", "wrong", "0"].contains(lower) {
            return false
        }

        return nil
    }

    /// Parse number from string (handles decimals, fractions, etc.)
    private func parseNumber(_ answer: String) -> Double? {
        // Remove common non-numeric characters
        let cleaned = answer
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")

        // Try direct conversion
        if let num = Double(cleaned) {
            return num
        }

        // Try to handle fractions (e.g., "1/2")
        if cleaned.contains("/") {
            let parts = cleaned.split(separator: "/")
            if parts.count == 2,
               let numerator = Double(parts[0]),
               let denominator = Double(parts[1]),
               denominator != 0 {
                return numerator / denominator
            }
        }

        return nil
    }

    /// Calculate string similarity using Levenshtein distance
    private func calculateStringSimilarity(_ s1: String, _ s2: String) -> Double {
        guard !s1.isEmpty && !s2.isEmpty else {
            return s1.isEmpty && s2.isEmpty ? 1.0 : 0.0
        }

        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        let similarity = 1.0 - (Double(distance) / Double(maxLength))

        return max(0.0, min(1.0, similarity))
    }

    /// Levenshtein distance calculation (edit distance)
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2.count + 1), count: s1.count + 1)

        for i in 0...s1.count {
            matrix[i][0] = i
        }

        for j in 0...s2.count {
            matrix[0][j] = j
        }

        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }

        return matrix[s1.count][s2.count]
    }
}
