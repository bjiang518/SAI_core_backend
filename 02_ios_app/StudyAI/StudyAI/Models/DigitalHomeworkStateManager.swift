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
        let newHash = generateHomeworkHash(image: image)

        // Check if this is a NEW homework (different image from current)
        if let existingHash = currentHomeworkHash, existingHash != newHash {
            // Reset to .nothing first
            currentState = .nothing
            currentHomework = nil
            currentHomeworkHash = nil
        } else if currentHomeworkHash == newHash {
            // Same homework - ignore redundant parse call
            return
        }

        // Convert image to data
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
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
    }

    /// Complete grading - State transition: Parsed → Graded
    func completeGrading(gradedQuestions: [ProgressiveQuestionWithGrade]) {
        guard var homework = currentHomework else {
            return
        }

        homework.questions = gradedQuestions
        homework.lastModified = Date()
        currentHomework = homework
        currentState = .graded
    }

    /// Update homework data (during grading, annotation, etc.)
    func updateHomework(questions: [ProgressiveQuestionWithGrade]? = nil,
                       annotations: [QuestionAnnotation]? = nil,
                       croppedImages: [Int: UIImage]? = nil) {
        guard var homework = currentHomework else {
            return
        }

        if let questions = questions {
            homework.questions = questions
        }

        if let annotations = annotations {
            homework.annotations = annotations
        }

        if let croppedImages = croppedImages {
            // ✅ FIX: Replace entire croppedImages dictionary (not just update entries)
            // This ensures deleted images are actually removed from the dictionary
            homework.croppedImages.removeAll()

            // Convert UIImages to Data and set all images
            for (questionId, image) in croppedImages {
                homework.setCroppedImage(image, for: questionId)
            }
        }

        homework.lastModified = Date()

        // ✅ FIX: Explicitly notify SwiftUI of changes before updating
        objectWillChange.send()
        currentHomework = homework
    }

    /// Revert grading - State transition: Graded → Parsed
    func revertGrading() {
        guard var homework = currentHomework else {
            return
        }

        guard currentState == .graded else {
            return
        }

        // Clear all grades but keep homework data
        homework.clearGrades()
        homework.lastModified = Date()
        currentHomework = homework
        currentState = .parsed
    }

    /// Clear all state - State transition: Any → Nothing
    func clearAll() {
        currentState = .nothing
        currentHomework = nil
        currentHomeworkHash = nil
        showResumePrompt = false
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
