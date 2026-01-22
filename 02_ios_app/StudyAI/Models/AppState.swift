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
    let questionImage: UIImage?  // ✅ NEW: Pro Mode cropped image

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
        // ✅ NEW: Add image as base64 if available
        if let image = questionImage,
           let jpegData = image.jpegData(compressionQuality: 0.85) {
            dict["question_image_base64"] = jpegData.base64EncodedString()
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

    /// Flag to indicate if the first message should use deep mode (o4)
    /// This is set when "Ask AI for Help" is triggered from practice questions
    @Published var shouldUseDeepModeForFirstMessage: Bool = false

    /// Selected tab
    @Published var selectedTab: MainTab = .home

    /// Power Saving Mode - disables all animations when enabled
    @Published var isPowerSavingMode: Bool {
        didSet {
            UserDefaults.standard.set(isPowerSavingMode, forKey: "isPowerSavingMode")
        }
    }

    private init() {
        // Load power saving mode from UserDefaults
        self.isPowerSavingMode = UserDefaults.standard.bool(forKey: "isPowerSavingMode")
    }

    /// Set a pending chat message and navigate to chat tab
    /// - Parameters:
    ///   - message: The message to send
    ///   - subject: Optional subject for the message
    ///   - useDeepMode: If true, the first message will use o4 deep thinking mode (default: false)
    func navigateToChatWithMessage(_ message: String, subject: String? = nil, useDeepMode: Bool = false) {
        pendingChatMessage = message
        pendingChatSubject = subject
        pendingHomeworkContext = nil  // Clear homework context for regular chat
        shouldUseDeepModeForFirstMessage = useDeepMode  // ✅ Set deep mode flag
        selectedTab = .chat
    }

    /// Set a pending homework question with context and navigate to chat tab
    func navigateToChatWithHomeworkQuestion(
        message: String,
        context: HomeworkQuestionContext
    ) {
        print("🔵 ============================================")
        print("🔵 === APPSTATE: SETTING HOMEWORK CONTEXT ===")
        print("🔵 ============================================")
        print("🔵 Timestamp: \(Date())")
        print("🔵 Thread: \(Thread.current)")
        print("📝 Full Message: \(message)")
        print("📚 Context Details:")
        print("   - Question Text: \(context.questionText)")
        print("   - Raw Question: \(context.rawQuestionText ?? "nil")")
        print("   - Student Answer: \(context.studentAnswer ?? "nil")")
        print("   - Correct Answer: \(context.correctAnswer ?? "nil")")
        print("   - Current Grade: \(context.currentGrade ?? "nil")")
        print("   - Original Feedback: \(context.originalFeedback ?? "nil")")
        print("   - Points: \(context.pointsEarned ?? 0)/\(context.pointsPossible ?? 0)")
        print("   - Subject: \(context.subject ?? "nil")")

        pendingChatMessage = message
        pendingChatSubject = context.subject
        pendingHomeworkContext = context

        print("✅ APPSTATE: Context stored in memory")
        print("✅ APPSTATE: pendingHomeworkContext is now: \(pendingHomeworkContext != nil ? "SET ✓" : "NIL ✗")")
        print("✅ APPSTATE: Memory address: \(Unmanaged.passUnretained(self).toOpaque())")
        print("✅ APPSTATE: Switching to .chat tab")
        print("🔵 ============================================")
        selectedTab = .chat
    }

    /// Clear the pending chat message (called after message is sent)
    func clearPendingChatMessage() {
        print("🔴 ============================================")
        print("🔴 === APPSTATE: CLEARING HOMEWORK CONTEXT ===")
        print("🔴 ============================================")
        print("🔴 Timestamp: \(Date())")
        print("🔴 Thread: \(Thread.current)")
        print("🔴 Called from: \(Thread.callStackSymbols[1])")
        print("🔴 Previous context existed: \(pendingHomeworkContext != nil)")
        if let context = pendingHomeworkContext {
            print("🔴 Clearing context for question: \(context.questionText)")
            print("🔴 Context had grade: \(context.currentGrade ?? "nil")")
        }

        pendingChatMessage = nil
        pendingChatSubject = nil
        pendingHomeworkContext = nil
        shouldUseDeepModeForFirstMessage = false  // ✅ Also clear deep mode flag

        print("🔴 APPSTATE: All pending data CLEARED")
        print("🔴 pendingHomeworkContext is now: \(pendingHomeworkContext != nil ? "SET ✓" : "NIL ✗")")
        print("🔴 ============================================")
    }

    /// Clear the deep mode flag (called after first message is sent with deep mode)
    func clearDeepModeFlag() {
        print("🧠 APPSTATE: Clearing deep mode flag")
        shouldUseDeepModeForFirstMessage = false
    }
}