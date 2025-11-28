//
//  DigitalHomeworkStateManager.swift
//  StudyAI
//
//  ✅ NEW: Global state manager for Digital Homework (State-based architecture)
//  Manages three states: Nothing → Parsed → Graded
//  State persists across tab switches, only resets on new homework parse
//

import Foundation
import SwiftUI
import Combine

// MARK: - Digital Homework State Enum

enum DigitalHomeworkState: String, Codable {
    case nothing    // No homework parsed
    case parsed     // Homework parsed, not graded yet
    case graded     // Homework graded
}

// MARK: - Digital Homework Data Model
// ✅ In-memory only - no Codable needed (no UserDefaults persistence)
struct DigitalHomeworkData {
    let homeworkHash: String  // Unique identifier for this homework
    let parseResults: ParseHomeworkQuestionsResponse
    let originalImageData: Data  // Store as Data for in-memory persistence
    var questions: [ProgressiveQuestionWithGrade]
    var annotations: [QuestionAnnotation]
    var croppedImages: [Int: Data]  // questionId -> image data (for in-memory storage)

    // Metadata
    let createdAt: Date
    var lastModified: Date

    // Progress tracking
    var hasMarkedProgress: Bool = false

    var originalImage: UIImage? {
        return UIImage(data: originalImageData)
    }

    func getCroppedImage(for questionId: Int) -> UIImage? {
        guard let imageData = croppedImages[questionId] else { return nil }
        return UIImage(data: imageData)
    }

    mutating func setCroppedImage(_ image: UIImage, for questionId: Int) {
        if let imageData = image.jpegData(compressionQuality: 0.85) {
            croppedImages[questionId] = imageData
        }
    }

    /// Clear all grades but keep homework data (for revert)
    mutating func clearGrades() {
        for i in 0..<questions.count {
            questions[i].grade = nil
            questions[i].isGrading = false
            questions[i].gradingError = nil

            if questions[i].isParentQuestion {
                questions[i].subquestionGrades.removeAll()
                questions[i].subquestionGradingStatus.removeAll()
                questions[i].subquestionErrors.removeAll()
            }

            // Keep isArchived flag (archived questions persist)
        }
    }
}

// MARK: - Global State Manager

@MainActor
class DigitalHomeworkStateManager: ObservableObject {
    static let shared = DigitalHomeworkStateManager()

    // MARK: - Published Properties (Global State)

    /// Current state of Digital Homework
    @Published var currentState: DigitalHomeworkState = .nothing

    /// Current homework data (nil when state is .nothing)
    @Published var currentHomework: DigitalHomeworkData?

    /// Show resume prompt when user returns to Pro Mode with existing homework
    @Published var showResumePrompt: Bool = false

    // MARK: - Private Properties

    private var currentHomeworkHash: String?

    private init() {
        // In-memory only (no UserDefaults persistence)
        print("✅ [StateManager] Initialized with in-memory state (no persistence)")
    }

    // MARK: - State Management Methods

    /// Generate unique hash for homework based on image content ONLY (no timestamp)
    /// This allows us to detect if the same image is being parsed again vs a new image
    private func generateHomeworkHash(image: UIImage) -> String {
        // Use ONLY image data hash for comparison (no timestamp)
        // This makes hash stable - same image = same hash
        let imageData = image.jpegData(compressionQuality: 0.1)
        let hashString = "\(imageData?.hashValue ?? 0)"
        return hashString
    }

    /// Parse new homework - State transition: Any → Nothing → Parsed
    func parseHomework(parseResults: ParseHomeworkQuestionsResponse, image: UIImage) {
        print("📋 [StateManager] parseHomework called")

        let newHash = generateHomeworkHash(image: image)
        print("   New homework hash: \(newHash)")
        print("   Current homework hash: \(currentHomeworkHash ?? "nil")")

        // Check if this is a NEW homework (different image from current)
        if let existingHash = currentHomeworkHash, existingHash != newHash {
            print("   🔄 NEW homework detected (different image) - resetting state")
            // Reset to .nothing first
            currentState = .nothing
            currentHomework = nil
            currentHomeworkHash = nil
        } else if currentHomeworkHash == newHash {
            print("   ⚠️ SAME homework detected (same image hash)")
            print("   This should not happen - HomeworkSummaryView should skip calling parseHomework()")
            print("   Ignoring redundant parse call")
            return
        }

        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            print("   ❌ Failed to convert image to data")
            return
        }

        // Create ungraded questions
        let ungradedQuestions = parseResults.questions.map { question in
            ProgressiveQuestionWithGrade(
                id: question.id,
                question: question,
                grade: nil,
                isGrading: false,
                gradingError: nil
            )
        }

        // Create new homework data
        let homeworkData = DigitalHomeworkData(
            homeworkHash: newHash,
            parseResults: parseResults,
            originalImageData: imageData,
            questions: ungradedQuestions,
            annotations: [],
            croppedImages: [:],
            createdAt: Date(),
            lastModified: Date()
        )

        // Update global state
        currentHomeworkHash = newHash
        currentHomework = homeworkData
        currentState = .parsed

        print("   ✅ State transition: → .parsed")
        print("   ✅ Homework data stored (in-memory)")
    }

    /// Complete grading - State transition: Parsed → Graded
    func completeGrading(gradedQuestions: [ProgressiveQuestionWithGrade]) {
        guard var homework = currentHomework else {
            print("⚠️ [StateManager] completeGrading: No current homework")
            return
        }

        print("📊 [StateManager] completeGrading called")
        print("   Graded questions: \(gradedQuestions.count)")

        homework.questions = gradedQuestions
        homework.lastModified = Date()
        currentHomework = homework
        currentState = .graded

        print("   ✅ State transition: .parsed → .graded")
    }

    /// Update homework data (during grading, annotation, etc.)
    func updateHomework(questions: [ProgressiveQuestionWithGrade]? = nil,
                       annotations: [QuestionAnnotation]? = nil,
                       croppedImages: [Int: UIImage]? = nil) {
        guard var homework = currentHomework else {
            print("⚠️ [StateManager] updateHomework: No current homework")
            return
        }

        if let questions = questions {
            homework.questions = questions
        }

        if let annotations = annotations {
            homework.annotations = annotations
        }

        if let croppedImages = croppedImages {
            // Convert UIImages to Data
            for (questionId, image) in croppedImages {
                homework.setCroppedImage(image, for: questionId)
            }
        }

        homework.lastModified = Date()

        // ✅ FIX: Explicitly notify SwiftUI of changes before updating
        objectWillChange.send()
        currentHomework = homework

        print("🔄 [StateManager] Homework data updated")
    }

    /// Revert grading - State transition: Graded → Parsed
    func revertGrading() {
        guard var homework = currentHomework else {
            print("⚠️ [StateManager] revertGrading: No current homework")
            return
        }

        guard currentState == .graded else {
            print("⚠️ [StateManager] revertGrading: Current state is not .graded")
            return
        }

        print("🔄 [StateManager] Reverting grading...")

        // Clear all grades but keep homework data
        homework.clearGrades()
        homework.lastModified = Date()
        currentHomework = homework
        currentState = .parsed

        print("   ✅ State transition: .graded → .parsed")
        print("   ✅ Grades cleared, homework data preserved")
    }

    /// Clear all state - State transition: Any → Nothing
    func clearAll() {
        print("🗑️ [StateManager] Clearing all state")

        currentState = .nothing
        currentHomework = nil
        currentHomeworkHash = nil
        showResumePrompt = false

        print("   ✅ State reset to .nothing")
    }

    /// Check if user should see resume prompt
    func checkResumePrompt() {
        // Show resume prompt if there's existing homework in parsed or graded state
        if currentState != .nothing && currentHomework != nil {
            showResumePrompt = true
            print("💡 [StateManager] Resume prompt enabled (existing homework found)")
        } else {
            showResumePrompt = false
        }
    }

    /// Resume existing homework (dismiss prompt and continue)
    func resumeHomework() {
        showResumePrompt = false
        print("▶️ [StateManager] Resuming existing homework (state: \(currentState))")
    }

    /// Start fresh (dismiss prompt and clear state)
    func startFresh() {
        showResumePrompt = false
        clearAll()
        print("🆕 [StateManager] Starting fresh (state cleared)")
    }
}
