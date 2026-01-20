//
//  ContextualButtonGenerator.swift
//  StudyAI
//
//  Refactored from SessionChatView.swift
//  Generates context-aware follow-up prompts based on AI response content
//

import Foundation

enum ContextualButtonGenerator {
    // MARK: - Generate Contextual Buttons

    static func generate(for message: String) -> [String] {
        let lowercaseMessage = message.lowercased()
        var suggestions: [String] = []

        // Math-related responses
        if containsMathTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.showSteps", comment: ""),
                NSLocalizedString("chat.suggestion.trySimilarProblem", comment: ""),
                NSLocalizedString("chat.suggestion.explainMethod", comment: "")
            ])
        }

        // Science concepts
        if containsScienceTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.realExamples", comment: ""),
                NSLocalizedString("chat.suggestion.howItWorks", comment: ""),
                NSLocalizedString("chat.suggestion.connectToDailyLife", comment: "")
            ])
        }

        // Definition or explanation responses
        if containsDefinitionTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.giveExamples", comment: ""),
                NSLocalizedString("chat.suggestion.compareWith", comment: ""),
                NSLocalizedString("chat.suggestion.useInSentence", comment: "")
            ])
        }

        // Problem-solving responses
        if containsProblemSolvingTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.explainWhy", comment: ""),
                NSLocalizedString("chat.suggestion.alternativeApproach", comment: ""),
                NSLocalizedString("chat.suggestion.practiceProblem", comment: "")
            ])
        }

        // Historical or factual content
        if containsHistoricalTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.whenDidThisHappen", comment: ""),
                NSLocalizedString("chat.suggestion.whoWasInvolved", comment: ""),
                NSLocalizedString("chat.suggestion.whatCausedThis", comment: "")
            ])
        }

        // Literature or language content
        if containsLiteratureTerms(lowercaseMessage) {
            suggestions.append(contentsOf: [
                NSLocalizedString("chat.suggestion.analyzeMeaning", comment: ""),
                NSLocalizedString("chat.suggestion.findThemes", comment: ""),
                NSLocalizedString("chat.suggestion.authorsIntent", comment: "")
            ])
        }

        // Remove duplicates and limit to 3
        let uniqueSuggestions = Array(Set(suggestions))

        if uniqueSuggestions.isEmpty {
            return [
                NSLocalizedString("chat.suggestion.explainDifferently", comment: ""),
                NSLocalizedString("chat.suggestion.giveExample", comment: ""),
                NSLocalizedString("chat.suggestion.moreDetails", comment: "")
            ]
        }

        return Array(uniqueSuggestions.prefix(3))
    }

    // MARK: - Generate Prompt

    static func generatePrompt(for buttonTitle: String, lastMessage: String) -> String {
        let localizedKeys: [String: String] = [
            NSLocalizedString("chat.suggestion.showSteps", comment: ""): "chat.prompt.showSteps",
            NSLocalizedString("chat.suggestion.trySimilarProblem", comment: ""): "chat.prompt.trySimilarProblem",
            NSLocalizedString("chat.suggestion.explainMethod", comment: ""): "chat.prompt.explainMethod",
            NSLocalizedString("chat.suggestion.giveExamples", comment: ""): "chat.prompt.giveExamples",
            NSLocalizedString("chat.suggestion.compareWith", comment: ""): "chat.prompt.compareWith",
            NSLocalizedString("chat.suggestion.useInSentence", comment: ""): "chat.prompt.useInSentence",
            NSLocalizedString("chat.suggestion.explainWhy", comment: ""): "chat.prompt.explainWhy",
            NSLocalizedString("chat.suggestion.alternativeApproach", comment: ""): "chat.prompt.alternativeApproach",
            NSLocalizedString("chat.suggestion.practiceProblem", comment: ""): "chat.prompt.practiceProblem",
            NSLocalizedString("chat.suggestion.realExamples", comment: ""): "chat.prompt.realExamples",
            NSLocalizedString("chat.suggestion.howItWorks", comment: ""): "chat.prompt.howItWorks",
            NSLocalizedString("chat.suggestion.connectToDailyLife", comment: ""): "chat.prompt.connectToDailyLife",
            NSLocalizedString("chat.suggestion.explainDifferently", comment: ""): "chat.prompt.explainDifferently",
            NSLocalizedString("chat.suggestion.giveExample", comment: ""): "chat.prompt.giveExample",
            NSLocalizedString("chat.suggestion.moreDetails", comment: ""): "chat.prompt.moreDetails"
        ]

        if let key = localizedKeys[buttonTitle] {
            return NSLocalizedString(key, comment: "")
        }

        return buttonTitle.lowercased()
    }

    // MARK: - Helper Methods

    private static func containsMathTerms(_ text: String) -> Bool {
        let mathTerms = ["solve", "equation", "=", "x", "y", "derivative", "integral", "function", "graph", "algebra", "geometry", "calculus", "trigonometry", "formula", "theorem", "proof"]
        return mathTerms.contains { text.contains($0) }
    }

    private static func containsScienceTerms(_ text: String) -> Bool {
        let scienceTerms = ["photosynthesis", "cell", "atom", "molecule", "chemical", "reaction", "energy", "force", "gravity", "electron", "proton", "dna", "protein", "evolution", "ecosystem", "planet", "solar"]
        return scienceTerms.contains { text.contains($0) }
    }

    private static func containsDefinitionTerms(_ text: String) -> Bool {
        let definitionTerms = ["define", "meaning", "refers to", "is a", "means that", "definition", "concept", "term"]
        return definitionTerms.contains { text.contains($0) }
    }

    private static func containsProblemSolvingTerms(_ text: String) -> Bool {
        let problemTerms = ["step", "first", "then", "next", "finally", "process", "method", "approach", "strategy", "solution"]
        return problemTerms.contains { text.contains($0) }
    }

    private static func containsHistoricalTerms(_ text: String) -> Bool {
        let historyTerms = ["war", "revolution", "empire", "century", "ancient", "medieval", "president", "king", "queen", "battle", "treaty", "civilization"]
        return historyTerms.contains { text.contains($0) }
    }

    private static func containsLiteratureTerms(_ text: String) -> Bool {
        let literatureTerms = ["character", "plot", "theme", "metaphor", "symbolism", "author", "poem", "novel", "story", "narrative", "analysis"]
        return literatureTerms.contains { text.contains($0) }
    }
}
