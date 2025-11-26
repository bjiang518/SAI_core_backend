//
//  DigitalHomeworkStateManager.swift
//  StudyAI
//
//  Persistent state manager for Digital Homework sessions
//  Saves grading results so users can return to graded homework after switching tabs
//

import Foundation
import SwiftUI
import Combine

@MainActor
class DigitalHomeworkStateManager: ObservableObject {
    static let shared = DigitalHomeworkStateManager()

    // MARK: - Published Properties

    /// Current session ID (unique identifier for this homework session)
    @Published var currentSessionId: String?

    /// Saved sessions (sessionId -> session data)
    @Published private(set) var savedSessions: [String: DigitalHomeworkSession] = [:]

    // MARK: - Private

    private init() {
        // Load saved sessions from UserDefaults on init
        loadSavedSessions()
    }

    // MARK: - Session Management

    /// Create or retrieve a session for the given parse results
    func getOrCreateSession(
        parseResults: ParseHomeworkQuestionsResponse,
        originalImage: UIImage,
        subject: String
    ) -> DigitalHomeworkSession {

        // Generate session ID from parse results (use hash of questions for uniqueness)
        let sessionId = generateSessionId(from: parseResults)

        // Check if session already exists
        if let existingSession = savedSessions[sessionId] {
            print("✅ Restored existing Digital Homework session: \(sessionId)")
            currentSessionId = sessionId
            return existingSession
        }

        // Create new session
        let newSession = DigitalHomeworkSession(
            sessionId: sessionId,
            parseResults: parseResults,
            originalImage: originalImage,
            subject: subject,
            questions: parseResults.questions.map { question in
                ProgressiveQuestionWithGrade(
                    id: question.id,
                    question: question,
                    grade: nil,
                    isGrading: false,
                    gradingError: nil
                )
            },
            createdAt: Date()
        )

        // Save session
        savedSessions[sessionId] = newSession
        currentSessionId = sessionId
        saveSessions()

        print("✅ Created new Digital Homework session: \(sessionId)")
        return newSession
    }

    /// Update grading results for a session
    func updateSession(
        sessionId: String,
        questions: [ProgressiveQuestionWithGrade],
        croppedImages: [Int: UIImage]
    ) {
        guard var session = savedSessions[sessionId] else {
            print("⚠️ Session not found: \(sessionId)")
            return
        }

        session.questions = questions
        session.croppedImages = croppedImages
        session.lastModified = Date()

        savedSessions[sessionId] = session
        saveSessions()

        print("✅ Updated Digital Homework session: \(sessionId)")
    }

    /// Clear current session
    func clearCurrentSession() {
        if let sessionId = currentSessionId {
            savedSessions.removeValue(forKey: sessionId)
            saveSessions()
            print("🗑️ Cleared session: \(sessionId)")
        }
        currentSessionId = nil
    }

    /// Clear all sessions (for debugging/reset)
    func clearAllSessions() {
        savedSessions.removeAll()
        currentSessionId = nil
        saveSessions()
        print("🗑️ Cleared all Digital Homework sessions")
    }

    // MARK: - Persistence

    private let sessionsKey = "DigitalHomeworkSessions"

    private func saveSessions() {
        // Convert sessions to dictionary for encoding
        let sessionsData = savedSessions.mapValues { session in
            session.toDictionary()
        }

        if let encoded = try? JSONEncoder().encode(sessionsData) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }

    private func loadSavedSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([String: [String: Data]].self, from: data) else {
            return
        }

        // Reconstruct sessions from saved data
        for (sessionId, sessionDict) in decoded {
            if let session = DigitalHomeworkSession.fromDictionary(sessionDict) {
                savedSessions[sessionId] = session
            }
        }

        print("✅ Loaded \(savedSessions.count) Digital Homework sessions")
    }

    // MARK: - Helpers

    private func generateSessionId(from parseResults: ParseHomeworkQuestionsResponse) -> String {
        // Generate unique session ID using content hash
        // This ensures each homework generates a unique ID, even if subject/question count are the same
        var hasher = Hasher()

        // Hash subject and total questions
        hasher.combine(parseResults.subject)
        hasher.combine(parseResults.totalQuestions)

        // Hash all question content to ensure uniqueness
        for question in parseResults.questions {
            hasher.combine(question.id)
            hasher.combine(question.questionText ?? "")
            hasher.combine(question.studentAnswer ?? "")
            hasher.combine(question.questionNumber ?? "")
        }

        // Add timestamp to ensure absolute uniqueness
        let timestamp = Int(Date().timeIntervalSince1970)
        hasher.combine(timestamp)

        let hashValue = abs(hasher.finalize())
        let identifier = "\(parseResults.subject)_\(parseResults.totalQuestions)_\(hashValue)"

        print("🔑 Generated session ID: \(identifier)")
        return identifier.replacingOccurrences(of: " ", with: "_")
    }
}

// MARK: - Digital Homework Session Model

struct DigitalHomeworkSession: Codable, Identifiable {
    let id = UUID()
    let sessionId: String
    let parseResults: ParseHomeworkQuestionsResponse
    let originalImageData: Data  // Store image as Data for persistence
    let subject: String
    var questions: [ProgressiveQuestionWithGrade]
    var croppedImages: [Int: UIImage]  // questionId -> cropped image
    let createdAt: Date
    var lastModified: Date

    init(
        sessionId: String,
        parseResults: ParseHomeworkQuestionsResponse,
        originalImage: UIImage,
        subject: String,
        questions: [ProgressiveQuestionWithGrade],
        createdAt: Date
    ) {
        self.sessionId = sessionId
        self.parseResults = parseResults
        self.originalImageData = originalImage.jpegData(compressionQuality: 0.8) ?? Data()
        self.subject = subject
        self.questions = questions
        self.croppedImages = [:]
        self.createdAt = createdAt
        self.lastModified = createdAt
    }

    var originalImage: UIImage? {
        return UIImage(data: originalImageData)
    }

    // Convert to dictionary for UserDefaults storage
    func toDictionary() -> [String: Data] {
        var dict: [String: Data] = [:]

        // Encode parse results
        if let parseData = try? JSONEncoder().encode(parseResults) {
            dict["parseResults"] = parseData
        }

        // Store image data
        dict["originalImageData"] = originalImageData

        // Encode questions
        if let questionsData = try? JSONEncoder().encode(questions) {
            dict["questionsData"] = questionsData
        }

        // Store metadata (including sessionId for proper restoration)
        if let metadata = try? JSONEncoder().encode([
            "sessionId": sessionId,
            "subject": subject,
            "createdAt": createdAt.timeIntervalSince1970,
            "lastModified": lastModified.timeIntervalSince1970
        ]) {
            dict["metadata"] = metadata
        }

        return dict
    }

    // Reconstruct from dictionary
    static func fromDictionary(_ dict: [String: Data]) -> DigitalHomeworkSession? {
        guard let parseData = dict["parseResults"],
              let parseResults = try? JSONDecoder().decode(ParseHomeworkQuestionsResponse.self, from: parseData),
              let imageData = dict["originalImageData"],
              let image = UIImage(data: imageData),
              let questionsData = dict["questionsData"],
              let questions = try? JSONDecoder().decode([ProgressiveQuestionWithGrade].self, from: questionsData),
              let metadataData = dict["metadata"],
              let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              let subject = metadata["subject"] as? String,
              let createdTimestamp = metadata["createdAt"] as? Double,
              let modifiedTimestamp = metadata["lastModified"] as? Double else {
            return nil
        }

        // Restore session ID from metadata (for sessions saved with new format)
        // Or generate new one if loading old format session
        let sessionId: String
        if let savedSessionId = metadata["sessionId"] as? String {
            sessionId = savedSessionId
            print("✅ Restored session ID from metadata: \(sessionId)")
        } else {
            // Legacy format: generate new hash-based ID
            var hasher = Hasher()
            hasher.combine(parseResults.subject)
            hasher.combine(parseResults.totalQuestions)
            for question in parseResults.questions {
                hasher.combine(question.id)
            }
            let hashValue = abs(hasher.finalize())
            sessionId = "\(parseResults.subject)_\(parseResults.totalQuestions)_\(hashValue)".replacingOccurrences(of: " ", with: "_")
            print("⚠️ Legacy session, generated new ID: \(sessionId)")
        }

        var session = DigitalHomeworkSession(
            sessionId: sessionId,
            parseResults: parseResults,
            originalImage: image,
            subject: subject,
            questions: questions,
            createdAt: Date(timeIntervalSince1970: createdTimestamp)
        )
        session.lastModified = Date(timeIntervalSince1970: modifiedTimestamp)

        return session
    }

    enum CodingKeys: String, CodingKey {
        case sessionId, parseResults, originalImageData, subject, questions, croppedImages, createdAt, lastModified
    }
}
