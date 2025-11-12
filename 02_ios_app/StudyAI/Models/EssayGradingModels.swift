//
//  EssayGradingModels.swift
//  StudyAI
//
//  Created by Claude Code on 11/10/25.
//

import Foundation
import SwiftUI

// MARK: - Essay Grading Result

/// Complete essay grading result with grammar corrections and criterion scores
struct EssayGradingResult: Codable, Identifiable {
    let id: UUID
    let essayTitle: String?
    let wordCount: Int

    // Grammar corrections with LaTeX formatting
    let grammarCorrections: [GrammarCorrection]

    // Criterion scores (0-10 scale)
    let criterionScores: EssayCriterionScores

    // Overall evaluation
    let overallScore: Float  // 0-100
    let overallFeedback: String

    // Computed properties
    var hasGrammarIssues: Bool {
        return !grammarCorrections.isEmpty
    }

    var grammarIssueCount: Int {
        return grammarCorrections.count
    }

    var performanceLevel: String {
        if overallScore >= 90 { return "Excellent" }
        else if overallScore >= 80 { return "Very Good" }
        else if overallScore >= 70 { return "Good" }
        else if overallScore >= 60 { return "Satisfactory" }
        else { return "Needs Improvement" }
    }

    init(id: UUID = UUID(),
         essayTitle: String?,
         wordCount: Int,
         grammarCorrections: [GrammarCorrection],
         criterionScores: EssayCriterionScores,
         overallScore: Float,
         overallFeedback: String) {
        self.id = id
        self.essayTitle = essayTitle
        self.wordCount = wordCount
        self.grammarCorrections = grammarCorrections
        self.criterionScores = criterionScores
        self.overallScore = overallScore
        self.overallFeedback = overallFeedback
    }
}

// MARK: - Grammar Correction

/// Individual grammar/style correction with LaTeX rendering support
struct GrammarCorrection: Codable, Identifiable {
    let id: UUID
    let sentenceNumber: Int
    let originalSentence: String
    let issueType: GrammarIssueType
    let explanation: String

    // LaTeX formatted correction (for rendering with HTML)
    // Example: "This \\sout{is} \\textcolor{green}{was} a mistake."
    let latexCorrection: String

    // Plain text correction (fallback)
    let plainCorrection: String

    init(id: UUID = UUID(),
         sentenceNumber: Int,
         originalSentence: String,
         issueType: GrammarIssueType,
         explanation: String,
         latexCorrection: String,
         plainCorrection: String) {
        self.id = id
        self.sentenceNumber = sentenceNumber
        self.originalSentence = originalSentence
        self.issueType = issueType
        self.explanation = explanation
        self.latexCorrection = latexCorrection
        self.plainCorrection = plainCorrection
    }
}

// MARK: - Grammar Issue Type

enum GrammarIssueType: String, Codable {
    case grammar = "grammar"
    case spelling = "spelling"
    case punctuation = "punctuation"
    case style = "style"
    case wordChoice = "word_choice"
    case structure = "structure"
    case clarity = "clarity"

    var displayName: String {
        switch self {
        case .grammar: return "Grammar"
        case .spelling: return "Spelling"
        case .punctuation: return "Punctuation"
        case .style: return "Style"
        case .wordChoice: return "Word Choice"
        case .structure: return "Structure"
        case .clarity: return "Clarity"
        }
    }

    var color: Color {
        switch self {
        case .grammar: return .red
        case .spelling: return .orange
        case .punctuation: return .blue
        case .style: return .purple
        case .wordChoice: return .indigo
        case .structure: return .teal
        case .clarity: return .pink
        }
    }

    var icon: String {
        switch self {
        case .grammar: return "exclamationmark.triangle"
        case .spelling: return "textformat.abc"
        case .punctuation: return "ellipsis"
        case .style: return "paintbrush"
        case .wordChoice: return "text.word.spacing"
        case .structure: return "list.bullet.indent"
        case .clarity: return "eye"
        }
    }
}

// MARK: - Essay Criterion Scores

/// All criterion scores for essay evaluation
struct EssayCriterionScores: Codable {
    let grammar: CriterionScore        // Grammar & mechanics
    let criticalThinking: CriterionScore  // Analysis & argumentation
    let organization: CriterionScore    // Structure & flow
    let coherence: CriterionScore      // Clarity & cohesion
    let vocabulary: CriterionScore     // Word choice & variety

    // Computed average
    var averageScore: Float {
        return (grammar.score + criticalThinking.score + organization.score +
                coherence.score + vocabulary.score) / 5.0
    }

    // Get all criteria as array for iteration
    var allCriteria: [(name: String, score: CriterionScore, icon: String, color: Color)] {
        return [
            ("Grammar & Mechanics", grammar, "text.badge.checkmark", .red),
            ("Critical Thinking", criticalThinking, "brain.head.profile", .blue),
            ("Organization", organization, "list.bullet.indent", .green),
            ("Coherence & Flow", coherence, "arrow.triangle.merge", .purple),
            ("Vocabulary & Style", vocabulary, "book.closed", .orange)
        ]
    }
}

// MARK: - Criterion Score

/// Individual criterion score with detailed feedback
struct CriterionScore: Codable {
    let score: Float  // 0-10
    let maxScore: Float
    let feedback: String
    let strengths: [String]
    let improvements: [String]

    // Computed properties
    var percentage: Float {
        return (score / maxScore) * 100
    }

    var performanceLevel: String {
        let percent = percentage
        if percent >= 90 { return "Excellent" }
        else if percent >= 80 { return "Very Good" }
        else if percent >= 70 { return "Good" }
        else if percent >= 60 { return "Satisfactory" }
        else { return "Needs Work" }
    }

    var color: Color {
        let percent = percentage
        if percent >= 80 { return .green }
        else if percent >= 60 { return .orange }
        else { return .red }
    }

    init(score: Float,
         maxScore: Float = 10.0,
         feedback: String,
         strengths: [String],
         improvements: [String]) {
        self.score = score
        self.maxScore = maxScore
        self.feedback = feedback
        self.strengths = strengths
        self.improvements = improvements
    }
}

// MARK: - Essay Grading Response Wrapper (for backend parsing)

/// Wrapper for backend API response
struct EssayGradingResponse: Codable {
    let essayTitle: String?
    let wordCount: Int
    let grammarCorrections: [GrammarCorrectionDTO]
    let criterionScores: EssayCriterionScoresDTO
    let overallScore: Float
    let overallFeedback: String

    enum CodingKeys: String, CodingKey {
        case essayTitle = "essay_title"
        case wordCount = "word_count"
        case grammarCorrections = "grammar_corrections"
        case criterionScores = "criterion_scores"
        case overallScore = "overall_score"
        case overallFeedback = "overall_feedback"
    }
}

// MARK: - Data Transfer Objects (DTOs for JSON parsing)

struct GrammarCorrectionDTO: Codable {
    let sentenceNumber: Int
    let originalSentence: String
    let issueType: String
    let explanation: String
    let latexCorrection: String
    let plainCorrection: String

    enum CodingKeys: String, CodingKey {
        case sentenceNumber = "sentence_number"
        case originalSentence = "original_sentence"
        case issueType = "issue_type"
        case explanation
        case latexCorrection = "latex_correction"
        case plainCorrection = "plain_correction"
    }

    func toModel() -> GrammarCorrection? {
        guard let issueType = GrammarIssueType(rawValue: issueType) else {
            return nil
        }
        return GrammarCorrection(
            sentenceNumber: sentenceNumber,
            originalSentence: originalSentence,
            issueType: issueType,
            explanation: explanation,
            latexCorrection: latexCorrection,
            plainCorrection: plainCorrection
        )
    }
}

struct EssayCriterionScoresDTO: Codable {
    let grammar: CriterionScoreDTO
    let criticalThinking: CriterionScoreDTO
    let organization: CriterionScoreDTO
    let coherence: CriterionScoreDTO
    let vocabulary: CriterionScoreDTO

    enum CodingKeys: String, CodingKey {
        case grammar
        case criticalThinking = "critical_thinking"
        case organization
        case coherence
        case vocabulary
    }

    func toModel() -> EssayCriterionScores {
        return EssayCriterionScores(
            grammar: grammar.toModel(),
            criticalThinking: criticalThinking.toModel(),
            organization: organization.toModel(),
            coherence: coherence.toModel(),
            vocabulary: vocabulary.toModel()
        )
    }
}

struct CriterionScoreDTO: Codable {
    let score: Float
    let feedback: String
    let strengths: [String]
    let improvements: [String]

    func toModel() -> CriterionScore {
        return CriterionScore(
            score: score,
            maxScore: 10.0,
            feedback: feedback,
            strengths: strengths,
            improvements: improvements
        )
    }
}
