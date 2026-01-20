//
//  SubjectHelpers.swift
//  StudyAI
//
//  Refactored from SessionChatView.swift
//  Provides subject-specific utilities for emojis, colors, and examples
//

import SwiftUI

enum SubjectHelpers {
    // MARK: - Subject Emoji

    static func emoji(for subject: String) -> String {
        switch subject {
        case "Mathematics": return "f(x)"
        case "Physics": return "⚛️"
        case "Chemistry": return "🧪"
        case "Biology": return "🧬"
        case "History": return "📜"
        case "Literature": return "📚"
        case "Geography": return "🌍"
        case "Computer Science": return "💻"
        case "Economics": return "📈"
        case "Psychology": return "🧠"
        case "Philosophy": return "💭"
        case "General": return "💡"
        default: return "💡"
        }
    }

    // MARK: - Background Color

    static func backgroundColor(for subject: String) -> Color {
        switch subject {
        case "Mathematics": return Color.blue.opacity(0.08)
        case "Physics": return Color.purple.opacity(0.08)
        case "Chemistry": return Color.green.opacity(0.08)
        case "Biology": return Color.mint.opacity(0.08)
        case "History": return Color.brown.opacity(0.08)
        case "Literature": return Color.indigo.opacity(0.08)
        case "Geography": return Color.teal.opacity(0.08)
        case "Computer Science": return Color.cyan.opacity(0.08)
        case "Economics": return Color.orange.opacity(0.08)
        case "Psychology": return Color.pink.opacity(0.08)
        case "Philosophy": return Color.gray.opacity(0.08)
        case "General": return Color.primary.opacity(0.05)
        default: return Color.primary.opacity(0.05)
        }
    }

    // MARK: - Example Prompts

    static func examplePrompts(for subject: String) -> [String] {
        let mathematics = NSLocalizedString("chat.subjects.mathematics", comment: "")
        let physics = NSLocalizedString("chat.subjects.physics", comment: "")
        let chemistry = NSLocalizedString("chat.subjects.chemistry", comment: "")
        let biology = NSLocalizedString("chat.subjects.biology", comment: "")
        let history = NSLocalizedString("chat.subjects.history", comment: "")
        let literature = NSLocalizedString("chat.subjects.literature", comment: "")
        let geography = NSLocalizedString("chat.subjects.geography", comment: "")
        let computerScience = NSLocalizedString("chat.subjects.computerScience", comment: "")
        let economics = NSLocalizedString("chat.subjects.economics", comment: "")
        let psychology = NSLocalizedString("chat.subjects.psychology", comment: "")
        let philosophy = NSLocalizedString("chat.subjects.philosophy", comment: "")
        let general = NSLocalizedString("chat.subjects.general", comment: "")

        switch subject {
        case mathematics:
            return [
                NSLocalizedString("chat.example.math.1", comment: ""),
                NSLocalizedString("chat.example.math.2", comment: ""),
                NSLocalizedString("chat.example.math.3", comment: ""),
                NSLocalizedString("chat.example.math.4", comment: "")
            ]
        case physics:
            return [
                NSLocalizedString("chat.example.physics.1", comment: ""),
                NSLocalizedString("chat.example.physics.2", comment: ""),
                NSLocalizedString("chat.example.physics.3", comment: ""),
                NSLocalizedString("chat.example.physics.4", comment: "")
            ]
        case chemistry:
            return [
                NSLocalizedString("chat.example.chemistry.1", comment: ""),
                NSLocalizedString("chat.example.chemistry.2", comment: ""),
                NSLocalizedString("chat.example.chemistry.3", comment: ""),
                NSLocalizedString("chat.example.chemistry.4", comment: "")
            ]
        case biology:
            return [
                NSLocalizedString("chat.example.biology.1", comment: ""),
                NSLocalizedString("chat.example.biology.2", comment: ""),
                NSLocalizedString("chat.example.biology.3", comment: ""),
                NSLocalizedString("chat.example.biology.4", comment: "")
            ]
        case history:
            return [
                NSLocalizedString("chat.example.history.1", comment: ""),
                NSLocalizedString("chat.example.history.2", comment: ""),
                NSLocalizedString("chat.example.history.3", comment: ""),
                NSLocalizedString("chat.example.history.4", comment: "")
            ]
        case literature:
            return [
                NSLocalizedString("chat.example.literature.1", comment: ""),
                NSLocalizedString("chat.example.literature.2", comment: ""),
                NSLocalizedString("chat.example.literature.3", comment: ""),
                NSLocalizedString("chat.example.literature.4", comment: "")
            ]
        case geography:
            return [
                NSLocalizedString("chat.example.geography.1", comment: ""),
                NSLocalizedString("chat.example.geography.2", comment: ""),
                NSLocalizedString("chat.example.geography.3", comment: ""),
                NSLocalizedString("chat.example.geography.4", comment: "")
            ]
        case computerScience:
            return [
                NSLocalizedString("chat.example.computerScience.1", comment: ""),
                NSLocalizedString("chat.example.computerScience.2", comment: ""),
                NSLocalizedString("chat.example.computerScience.3", comment: ""),
                NSLocalizedString("chat.example.computerScience.4", comment: "")
            ]
        case economics:
            return [
                NSLocalizedString("chat.example.economics.1", comment: ""),
                NSLocalizedString("chat.example.economics.2", comment: ""),
                NSLocalizedString("chat.example.economics.3", comment: ""),
                NSLocalizedString("chat.example.economics.4", comment: "")
            ]
        case psychology:
            return [
                NSLocalizedString("chat.example.psychology.1", comment: ""),
                NSLocalizedString("chat.example.psychology.2", comment: ""),
                NSLocalizedString("chat.example.psychology.3", comment: ""),
                NSLocalizedString("chat.example.psychology.4", comment: "")
            ]
        case philosophy:
            return [
                NSLocalizedString("chat.example.philosophy.1", comment: ""),
                NSLocalizedString("chat.example.philosophy.2", comment: ""),
                NSLocalizedString("chat.example.philosophy.3", comment: ""),
                NSLocalizedString("chat.example.philosophy.4", comment: "")
            ]
        case general:
            return [
                NSLocalizedString("chat.example.general.1", comment: ""),
                NSLocalizedString("chat.example.general.2", comment: ""),
                NSLocalizedString("chat.example.general.3", comment: ""),
                NSLocalizedString("chat.example.general.4", comment: "")
            ]
        default:
            return [
                NSLocalizedString("chat.example.default.1", comment: ""),
                NSLocalizedString("chat.example.default.2", comment: ""),
                NSLocalizedString("chat.example.default.3", comment: ""),
                NSLocalizedString("chat.example.default.4", comment: "")
            ]
        }
    }
}
