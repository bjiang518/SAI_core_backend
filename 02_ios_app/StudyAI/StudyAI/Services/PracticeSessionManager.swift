//
//  PracticeSessionManager.swift
//  StudyAI
//
//  Session persistence for practice questions
//  Prevents loss of progress when app is backgrounded
//

import Foundation
import SwiftUI
import Combine

/// Manages persistence of practice question sessions
class PracticeSessionManager: ObservableObject {
    static let shared = PracticeSessionManager()

    private let userDefaults = UserDefaults.standard
    private let sessionsKey = "practice_sessions"
    private let logger = AppLogger.forFeature("PracticeSession")

    @Published var hasIncompleteSessions = false
    @Published var incompleteSessions: [PracticeSession] = []

    private init() {
        loadSessions()
    }

    // MARK: - Session Management

    /// Save a new practice session
    /// - Returns: The session ID for tracking progress
    @discardableResult
    func saveSession(
        questions: [QuestionGenerationService.GeneratedQuestion],
        generationType: String,
        subject: String,
        config: QuestionGenerationService.RandomQuestionsConfig
    ) -> String {
        let session = PracticeSession(
            id: UUID().uuidString,
            questions: questions,
            generationType: generationType,
            subject: subject,
            difficulty: config.difficulty.rawValue,
            questionType: config.questionType.rawValue,
            createdDate: Date(),
            lastAccessedDate: Date(),
            completedQuestionIds: [],
            answers: [:]
        )

        var sessions = loadAllSessions()
        sessions.append(session)

        // Keep only last 10 sessions
        if sessions.count > 10 {
            sessions = Array(sessions.suffix(10))
        }

        saveSessions(sessions)
        updatePublishedState()

        logger.info("📝 Saved practice session: \(session.id) (\(questions.count) questions, type: \(generationType))")

        return session.id  // ✅ FIX: Return session ID
    }

    /// Update progress for a session
    func updateProgress(
        sessionId: String,
        completedQuestionId: String,
        answer: String?,
        isCorrect: Bool?
    ) {
        var sessions = loadAllSessions()

        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else {
            logger.warning("⚠️ Session not found: \(sessionId)")
            return
        }

        var session = sessions[index]

        // Add to completed questions
        if !session.completedQuestionIds.contains(completedQuestionId) {
            session.completedQuestionIds.append(completedQuestionId)
        }

        // Save answer
        if let answer = answer {
            var answerData: [String: Any] = ["answer": answer]
            if let isCorrect = isCorrect {
                answerData["is_correct"] = isCorrect
            }
            answerData["timestamp"] = Date().timeIntervalSince1970
            session.answers[completedQuestionId] = answerData
        }

        session.lastAccessedDate = Date()
        sessions[index] = session

        saveSessions(sessions)
        updatePublishedState()

        logger.debug("✅ Updated session \(sessionId): \(session.completedQuestionIds.count)/\(session.questions.count) questions completed")
    }

    /// Get a specific session
    func getSession(id: String) -> PracticeSession? {
        return loadAllSessions().first { $0.id == id }
    }

    /// Get all incomplete sessions
    func getIncompleteSessions() -> [PracticeSession] {
        let sessions = loadAllSessions()
        return sessions.filter { !$0.isCompleted }
            .sorted { $0.lastAccessedDate > $1.lastAccessedDate }
    }

    /// Delete a session
    func deleteSession(id: String) {
        var sessions = loadAllSessions()
        sessions.removeAll { $0.id == id }
        saveSessions(sessions)
        updatePublishedState()

        logger.info("🗑️ Deleted session: \(id)")
    }

    /// Clear all completed sessions older than 7 days
    func clearOldCompletedSessions() {
        let weekAgo = Date().addingTimeInterval(-7 * 86400)
        var sessions = loadAllSessions()

        let beforeCount = sessions.count
        sessions.removeAll { session in
            session.isCompleted && session.lastAccessedDate < weekAgo
        }

        let removedCount = beforeCount - sessions.count

        if removedCount > 0 {
            saveSessions(sessions)
            updatePublishedState()
            logger.info("🧹 Cleared \(removedCount) old completed sessions")
        }
    }

    // MARK: - Private Helpers

    private func loadAllSessions() -> [PracticeSession] {
        guard let data = userDefaults.data(forKey: sessionsKey) else {
            return []
        }

        do {
            let sessions = try JSONDecoder().decode([PracticeSession].self, from: data)
            return sessions
        } catch {
            logger.error("❌ Failed to decode sessions: \(error.localizedDescription)")
            return []
        }
    }

    private func saveSessions(_ sessions: [PracticeSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            userDefaults.set(data, forKey: sessionsKey)
            logger.debug("💾 Saved \(sessions.count) sessions to UserDefaults")
        } catch {
            logger.error("❌ Failed to encode sessions: \(error.localizedDescription)")
        }
    }

    private func loadSessions() {
        updatePublishedState()
    }

    private func updatePublishedState() {
        DispatchQueue.main.async {
            self.incompleteSessions = self.getIncompleteSessions()
            self.hasIncompleteSessions = !self.incompleteSessions.isEmpty
        }
    }
}

// MARK: - Data Models

struct PracticeSession: Codable, Identifiable {
    let id: String
    let questions: [QuestionGenerationService.GeneratedQuestion]
    let generationType: String  // "Random Practice", "Mistake-Based", "Conversation-Based"
    let subject: String
    let difficulty: String
    let questionType: String
    let createdDate: Date
    var lastAccessedDate: Date
    var completedQuestionIds: [String]
    var answers: [String: [String: Any]]  // questionId -> {answer, is_correct, timestamp}

    var isCompleted: Bool {
        completedQuestionIds.count == questions.count
    }

    var progressPercentage: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(completedQuestionIds.count) / Double(questions.count)
    }

    var remainingQuestions: Int {
        questions.count - completedQuestionIds.count
    }

    // Custom coding for dictionary with Any values
    enum CodingKeys: String, CodingKey {
        case id, questions, generationType, subject, difficulty, questionType
        case createdDate, lastAccessedDate, completedQuestionIds, answers
    }

    init(id: String, questions: [QuestionGenerationService.GeneratedQuestion], generationType: String, subject: String, difficulty: String, questionType: String, createdDate: Date, lastAccessedDate: Date, completedQuestionIds: [String], answers: [String: [String: Any]]) {
        self.id = id
        self.questions = questions
        self.generationType = generationType
        self.subject = subject
        self.difficulty = difficulty
        self.questionType = questionType
        self.createdDate = createdDate
        self.lastAccessedDate = lastAccessedDate
        self.completedQuestionIds = completedQuestionIds
        self.answers = answers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        questions = try container.decode([QuestionGenerationService.GeneratedQuestion].self, forKey: .questions)
        generationType = try container.decode(String.self, forKey: .generationType)
        subject = try container.decode(String.self, forKey: .subject)
        difficulty = try container.decode(String.self, forKey: .difficulty)
        questionType = try container.decode(String.self, forKey: .questionType)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        lastAccessedDate = try container.decode(Date.self, forKey: .lastAccessedDate)
        completedQuestionIds = try container.decode([String].self, forKey: .completedQuestionIds)

        // Decode answers dictionary
        if let answersData = try? container.decode([String: CodableAnswer].self, forKey: .answers) {
            self.answers = answersData.mapValues { $0.toDictionary() }
        } else {
            self.answers = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(questions, forKey: .questions)
        try container.encode(generationType, forKey: .generationType)
        try container.encode(subject, forKey: .subject)
        try container.encode(difficulty, forKey: .difficulty)
        try container.encode(questionType, forKey: .questionType)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(lastAccessedDate, forKey: .lastAccessedDate)
        try container.encode(completedQuestionIds, forKey: .completedQuestionIds)

        // Encode answers dictionary
        let codableAnswers = answers.mapValues { CodableAnswer(dictionary: $0) }
        try container.encode(codableAnswers, forKey: .answers)
    }
}

// Helper struct for encoding/decoding answer dictionaries
private struct CodableAnswer: Codable {
    let answer: String
    let isCorrect: Bool?
    let timestamp: Double

    init(dictionary: [String: Any]) {
        self.answer = dictionary["answer"] as? String ?? ""
        self.isCorrect = dictionary["is_correct"] as? Bool
        self.timestamp = dictionary["timestamp"] as? Double ?? Date().timeIntervalSince1970
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "answer": answer,
            "timestamp": timestamp
        ]
        if let isCorrect = isCorrect {
            dict["is_correct"] = isCorrect
        }
        return dict
    }
}

// MARK: - Resume Session View

struct ResumeSessionBanner: View {
    let session: PracticeSession
    let onResume: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.orange)
                    Text("Resume Practice")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text("\(session.generationType) • \(session.remainingQuestions) questions left")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange)
                            .frame(width: geometry.size.width * session.progressPercentage, height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(spacing: 8) {
                Button(action: onResume) {
                    Text("Resume")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.orange)
                        .cornerRadius(8)
                }

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
