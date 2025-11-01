//
//  AppState.swift
//  StudyAI
//
//  Created by Claude Code on 10/7/25.
//

import SwiftUI
import Combine

/// Homework question context for follow-up AI chat
struct HomeworkQuestionContext {
    let questionText: String
    let rawQuestionText: String?
    let studentAnswer: String?
    let correctAnswer: String?
    let currentGrade: String?  // CORRECT, INCORRECT, EMPTY, PARTIAL_CREDIT
    let originalFeedback: String?
    let pointsEarned: Float?
    let pointsPossible: Float?
    let questionNumber: Int?
    let subject: String?

    /// Convert to dictionary for network request
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "question_text": questionText
        ]

        if let raw = rawQuestionText {
            dict["raw_question_text"] = raw
        }
        if let answer = studentAnswer {
            dict["student_answer"] = answer
        }
        if let correct = correctAnswer {
            dict["correct_answer"] = correct
        }
        if let grade = currentGrade {
            dict["current_grade"] = grade
        }
        if let feedback = originalFeedback {
            dict["original_feedback"] = feedback
        }
        if let earned = pointsEarned {
            dict["points_earned"] = earned
        }
        if let possible = pointsPossible {
            dict["points_possible"] = possible
        }
        if let number = questionNumber {
            dict["question_number"] = number
        }
        if let subj = subject {
            dict["subject"] = subj
        }

        return dict
    }
}

/// Global app state for managing cross-tab communication
class AppState: ObservableObject {
    static let shared = AppState()

    /// Pending chat message to be sent when user navigates to chat
    @Published var pendingChatMessage: String?

    /// Subject for the pending chat message
    @Published var pendingChatSubject: String?

    /// Pending homework question context for AI follow-up
    @Published var pendingHomeworkContext: HomeworkQuestionContext?

    /// Selected tab
    @Published var selectedTab: MainTab = .home

    private init() {}

    /// Set a pending chat message and navigate to chat tab
    func navigateToChatWithMessage(_ message: String, subject: String? = nil) {
        pendingChatMessage = message
        pendingChatSubject = subject
        pendingHomeworkContext = nil  // Clear homework context for regular chat
        selectedTab = .chat
    }

    /// Set a pending homework question with context and navigate to chat tab
    func navigateToChatWithHomeworkQuestion(
        message: String,
        context: HomeworkQuestionContext
    ) {
        print("🔵 === APPSTATE: SETTING HOMEWORK CONTEXT ===")
        print("📝 Message Preview: \(message.prefix(100))")
        print("📚 Context Question: \(context.questionText.prefix(100))")
        print("📚 Context Subject: \(context.subject ?? "nil")")
        print("📚 Context Current Grade: \(context.currentGrade ?? "nil")")

        pendingChatMessage = message
        pendingChatSubject = context.subject
        pendingHomeworkContext = context

        print("✅ APPSTATE: Context stored successfully")
        print("✅ APPSTATE: Switching to .chat tab")
        selectedTab = .chat
    }

    /// Clear the pending chat message (called after message is sent)
    func clearPendingChatMessage() {
        print("🔴 === APPSTATE: CLEARING HOMEWORK CONTEXT ===")
        print("🔴 Previous context existed: \(pendingHomeworkContext != nil)")
        if let context = pendingHomeworkContext {
            print("🔴 Clearing context for question: \(context.questionText.prefix(100))")
        }

        pendingChatMessage = nil
        pendingChatSubject = nil
        pendingHomeworkContext = nil

        print("🔴 APPSTATE: All pending data cleared")
    }
}