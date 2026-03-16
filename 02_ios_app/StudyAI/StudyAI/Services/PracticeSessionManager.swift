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
import PDFKit

/// Manages persistence of practice question sessions
class PracticeSessionManager: ObservableObject {
    static let shared = PracticeSessionManager()

    private let userDefaults = UserDefaults.standard
    private var authCancellable: AnyCancellable?
    private var uid: String { AuthenticationService.shared.currentUser?.id ?? "anonymous" }
    private var sessionsKey: String { "practice_sessions_\(uid)" }
    private let logger = AppLogger.forFeature("PracticeSession")

    @Published var hasIncompleteSessions = false
    @Published var incompleteSessions: [PracticeSession] = []
    @Published var allSessionsPublished: [PracticeSession] = []

    private init() {
        loadSessions()
        authCancellable = AuthenticationService.shared.$isAuthenticated
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadSessions() }
    }

    // MARK: - Session Management

    /// Save a new practice session
    /// - Returns: The saved PracticeSession
    @discardableResult
    func saveSession(
        questions: [QuestionGenerationService.GeneratedQuestion],
        generationType: String,
        subject: String,
        config: QuestionGenerationService.RandomQuestionsConfig
    ) -> PracticeSession {
        let session = PracticeSession(
            id: UUID().uuidString,
            questions: questions,
            generationType: generationType,
            subject: PracticeSessionManager.normalizeSubject(subject),
            difficulty: config.difficulty.rawValue,
            questionType: config.questionType.rawValue,
            createdDate: Date(),
            lastAccessedDate: Date(),
            completedQuestionIds: [],
            answers: [:]
        )

        var sessions = loadAllSessions()
        sessions.append(session)

        // Cap at 50 sessions — prune oldest completed sessions first
        if sessions.count > 50 {
            let completed = sessions.filter { $0.isCompleted }.sorted { $0.lastAccessedDate < $1.lastAccessedDate }
            let toRemove = sessions.count - 50
            let idsToRemove = Set(completed.prefix(toRemove).map { $0.id })
            sessions.removeAll { idsToRemove.contains($0.id) }
        }

        saveSessions(sessions)
        updatePublishedState()

        logger.info("📝 Saved practice session: \(session.id) (\(questions.count) questions, type: \(generationType))")

        Task { await syncSessionCreated(session) }
        Task { await generateAndStorePDF(for: session) }

        return session
    }

    /// Save a session with an explicit PracticeSession object (for mistake/weakness flows)
    @discardableResult
    func saveSession(_ session: PracticeSession) -> PracticeSession {
        let normalizedSubject = PracticeSessionManager.normalizeSubject(session.subject)
        let sessionToSave: PracticeSession
        if normalizedSubject != session.subject {
            sessionToSave = PracticeSession(
                id: session.id,
                questions: session.questions,
                generationType: session.generationType,
                subject: normalizedSubject,
                difficulty: session.difficulty,
                questionType: session.questionType,
                createdDate: session.createdDate,
                lastAccessedDate: session.lastAccessedDate,
                completedQuestionIds: session.completedQuestionIds,
                answers: session.answers,
                isOrganized: session.isOrganized
            )
        } else {
            sessionToSave = session
        }

        var sessions = loadAllSessions()
        sessions.append(sessionToSave)

        if sessions.count > 50 {
            let completed = sessions.filter { $0.isCompleted }.sorted { $0.lastAccessedDate < $1.lastAccessedDate }
            let toRemove = sessions.count - 50
            let idsToRemove = Set(completed.prefix(toRemove).map { $0.id })
            sessions.removeAll { idsToRemove.contains($0.id) }
        }

        saveSessions(sessions)
        updatePublishedState()

        logger.info("📝 Saved session (direct): \(sessionToSave.id) (\(sessionToSave.questions.count) questions)")
        Task { await syncSessionCreated(sessionToSave) }
        Task { await generateAndStorePDF(for: sessionToSave) }

        return sessionToSave
    }

    /// Delete a single question from a session (updates local storage)
    func deleteQuestion(sessionId: String, questionId: String) {
        var sessions = loadAllSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let current = sessions[index]
        var updatedAnswers = current.answers
        updatedAnswers.removeValue(forKey: questionId)
        let updatedSession = PracticeSession(
            id: current.id,
            questions: current.questions.filter { $0.id.uuidString != questionId },
            generationType: current.generationType,
            subject: current.subject,
            difficulty: current.difficulty,
            questionType: current.questionType,
            createdDate: current.createdDate,
            lastAccessedDate: Date(),
            completedQuestionIds: current.completedQuestionIds.filter { $0 != questionId },
            answers: updatedAnswers,
            isOrganized: current.isOrganized
        )
        sessions[index] = updatedSession
        saveSessions(sessions)
        updatePublishedState()
        logger.info("🗑️ Deleted question \(questionId) from session \(sessionId)")
    }

    /// Normalize + localize a raw subject string for display.
    /// Delegates to BranchLocalizer which uses Taxonomy.strings — the same table
    /// used everywhere else in the app for subject/topic names.
    /// "Others: Science" → strips prefix, localizes suffix → "Science" / "科学"
    static func localizeSubject(_ raw: String) -> String {
        if raw.hasPrefix("Others: ") {
            let suffix = String(raw.dropFirst("Others: ".count))
            return BranchLocalizer.localized(suffix)
        }
        return BranchLocalizer.localized(normalizeSubject(raw))
    }

    /// Normalize a raw subject string to the canonical form used throughout the app.
    /// Maps common variants (e.g. "Math", "Maths") to the canonical name ("Mathematics")
    /// so that the Practice Library always groups sessions under one consistent subject chip.
    static func normalizeSubject(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "math", "maths", "mathematics": return "Mathematics"
        case "physics": return "Physics"
        case "chemistry": return "Chemistry"
        case "biology": return "Biology"
        case "english", "english language", "language arts", "ela": return "English"
        case "history", "world history", "us history", "american history": return "History"
        case "geography": return "Geography"
        case "computer science", "cs", "coding", "programming": return "Computer Science"
        case "literature", "english literature": return "Literature"
        case "social studies": return "Social Studies"
        case "economics": return "Economics"
        case "art": return "Art"
        case "music": return "Music"
        case "science", "general science": return "Science"
        case "other": return "Other"
        default: return trimmed
        }
    }

    /// Convert a WeaknessPracticeQuestion into a GeneratedQuestion for the unified session model
    static func convert(_ q: WeaknessPracticeQuestion, subject: String) -> QuestionGenerationService.GeneratedQuestion {
        let qType: QuestionGenerationService.GeneratedQuestion.QuestionType
        switch q.questionType {
        case "multiple_choice": qType = .multipleChoice
        case "true_false":      qType = .trueFalse
        case "short_answer":    qType = .shortAnswer
        case "long_answer":     qType = .longAnswer
        case "fill_blank":      qType = .fillBlank
        case "calculation":     qType = .calculation
        case "matching":        qType = .matching
        default:                qType = .shortAnswer
        }

        return QuestionGenerationService.GeneratedQuestion(
            id: q.id,
            question: q.questionText,
            type: qType,
            correctAnswer: q.correctAnswer,
            explanation: "",
            topic: subject,
            difficulty: "intermediate",
            points: 1,
            timeEstimate: nil,
            options: q.options,
            tags: nil,
            errorType: nil,
            baseBranch: nil,
            detailedBranch: nil,
            weaknessKey: q.weaknessKey
        )
    }

    // MARK: - Backend Sync

    /// Fire-and-forget sync on create — failures are silently logged
    func syncSessionCreated(_ session: PracticeSession) async {
        let sourceType: String
        let generationMode: Int
        switch session.generationType {
        case "Mistake-Based Practice", "Mistake-Based":
            sourceType = "mistake"; generationMode = 2
        case "Conversation-Based", "Conversation-Based Practice":
            sourceType = "archive"; generationMode = 3
        default:
            sourceType = "random"; generationMode = 1
        }

        do {
            try await NetworkService.shared.createPracticeSheet(
                sheetId: session.id,
                subject: session.subject,
                sourceType: sourceType,
                questionCount: session.questions.count,
                generationMode: generationMode,
                difficulty: session.difficulty
            )
        } catch {
            logger.warning("⚠️ Practice sheet sync (create) failed (non-fatal): \(error.localizedDescription)")
        }
    }

    /// Fire-and-forget sync on complete — failures are silently logged
    func syncSessionCompleted(_ session: PracticeSession) async {
        let correct = session.answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        let total = session.completedQuestionIds.count
        let scorePct = total > 0 ? Double(correct) / Double(total) * 100.0 : 0.0

        do {
            try await NetworkService.shared.completePracticeSheet(
                sheetId: session.id,
                completedCount: total,
                scorePercentage: scorePct,
                timeSpentSeconds: session.timeSpentSeconds
            )
        } catch {
            logger.warning("⚠️ Practice sheet sync (complete) failed (non-fatal): \(error.localizedDescription)")
        }
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

    /// Public accessor for all sessions (for PracticeLibraryView)
    func loadAllSessionsPublic() -> [PracticeSession] {
        return loadAllSessions()
    }

    /// Get all incomplete sessions
    func getIncompleteSessions() -> [PracticeSession] {
        let sessions = loadAllSessions()
        return sessions.filter { !$0.isCompleted }
            .sorted { $0.lastAccessedDate > $1.lastAccessedDate }
    }

    /// Delete a session
    // MARK: - PDF Generation

    /// Generate a PDF for the given session in the background and persist the file name.
    /// Safe to call multiple times — skips if the file already exists on disk.
    func generateAndStorePDF(for session: PracticeSession) async {
        let fileName = "practice_\(session.id).pdf"
        guard let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let fileURL = docDir.appendingPathComponent(fileName)

        // Skip if already on disk
        if FileManager.default.fileExists(atPath: fileURL.path) {
            if session.pdfFileName == nil {
                updateSessionPDFFileName(sessionId: session.id, fileName: fileName)
            }
            return
        }

        let pdfGenerator = PDFGeneratorService()
        guard let doc = await pdfGenerator.generatePracticePDF(
            questions: session.questions,
            subject: session.subject,
            generationType: session.generationType
        ) else { return }

        if let data = doc.dataRepresentation(),
           (try? data.write(to: fileURL)) != nil {
            updateSessionPDFFileName(sessionId: session.id, fileName: fileName)
            logger.info("📄 PDF stored for session \(session.id): \(fileName)")
        }
    }

    private func updateSessionPDFFileName(sessionId: String, fileName: String) {
        var sessions = loadAllSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].pdfFileName = fileName
        saveSessions(sessions)
        DispatchQueue.main.async { [weak self] in self?.updatePublishedState() }
    }

    func deleteSession(id: String) {
        // Delete associated PDF file if it exists
        if let session = loadAllSessions().first(where: { $0.id == id }),
           let url = session.pdfFileURL {
            try? FileManager.default.removeItem(at: url)
        }
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

    /// Mark a session as organized (Smart Organize was used). Persists across re-entry.
    func markOrganized(sessionId: String) {
        var sessions = loadAllSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].isOrganized = true
        saveSessions(sessions)
        updatePublishedState()
    }

    /// Reset all answers for a session so the user can redo it from scratch.
    /// Preserves the isOrganized flag so the Smart Organize banner stays dismissed.
    func resetSessionProgress(sessionId: String) {
        var sessions = loadAllSessions()
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        let current = sessions[index]
        let reset = PracticeSession(
            id: current.id,
            questions: current.questions,
            generationType: current.generationType,
            subject: current.subject,
            difficulty: current.difficulty,
            questionType: current.questionType,
            createdDate: current.createdDate,
            lastAccessedDate: Date(),
            completedQuestionIds: [],
            answers: [:],
            isOrganized: current.isOrganized
        )
        sessions[index] = reset
        saveSessions(sessions)
        updatePublishedState()
        logger.info("🔄 Reset progress for session \(sessionId)")
    }

    func updatePublishedState() {
        let applyUpdate = {
            self.allSessionsPublished = self.loadAllSessions()
            self.incompleteSessions = self.allSessionsPublished.filter { !$0.isCompleted }
                .sorted { $0.lastAccessedDate > $1.lastAccessedDate }
            self.hasIncompleteSessions = !self.incompleteSessions.isEmpty
        }
        // If already on main thread (e.g. called from @MainActor views), assign directly
        // so the @Published update fires in the same runloop cycle — no stale-frame delay.
        if Thread.isMainThread {
            applyUpdate()
        } else {
            DispatchQueue.main.async(execute: applyUpdate)
        }
    }
}

// MARK: - Data Models

struct PracticeSession: Codable, Identifiable, Hashable {
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
    var isOrganized: Bool
    var pdfFileName: String?   // filename inside Documents dir, set after background PDF generation

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

    /// Resolved URL for the cached PDF file on disk.
    var pdfFileURL: URL? {
        guard let name = pdfFileName else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }
    /// Score percentage (0–100) based on answered questions. nil if nothing answered yet.
    var scorePercentage: Double? {
        guard !completedQuestionIds.isEmpty else { return nil }
        let correct = answers.values.filter { ($0["is_correct"] as? Bool) == true }.count
        return Double(correct) / Double(completedQuestionIds.count) * 100.0
    }

    /// Time spent in seconds, derived from first and last answer timestamps.
    var timeSpentSeconds: Int? {
        let timestamps = answers.values.compactMap { $0["timestamp"] as? Double }
        guard let first = timestamps.min(), let last = timestamps.max(), last > first else { return nil }
        return Int(last - first)
    }

    var localizedGenerationType: String {
        switch generationType {
        case "Random Practice":
            return NSLocalizedString("questionGeneration.type.random", comment: "")
        case "Conversation-Based", "Conversation-Based Practice":
            return NSLocalizedString("questionGeneration.type.conversationBased", comment: "")
        case "Mistake-Based", "Mistake-Based Practice":
            return NSLocalizedString("questionGeneration.type.mistakeBased", comment: "")
        case "Library-Selection":
            return NSLocalizedString("questionGeneration.type.librarySelection", value: "Library", comment: "")
        default:
            return generationType
        }
    }

    var generationTypeColor: Color {
        switch generationType {
        case "Random Practice": return .blue
        case "Conversation-Based", "Conversation-Based Practice": return .green
        case "Mistake-Based", "Mistake-Based Practice": return .orange
        case "Library-Selection": return .teal
        default: return .blue
        }
    }

    var generationTypeIcon: String {
        switch generationType {
        case "Random Practice": return "dice.fill"
        case "Conversation-Based", "Conversation-Based Practice": return "books.vertical.fill"
        case "Mistake-Based", "Mistake-Based Practice": return "exclamationmark.triangle.fill"
        case "Library-Selection": return "doc.text.fill"
        default: return "questionmark.circle.fill"
        }
    }

    // Custom coding for dictionary with Any values
    enum CodingKeys: String, CodingKey {
        case id, questions, generationType, subject, difficulty, questionType
        case createdDate, lastAccessedDate, completedQuestionIds, answers, isOrganized
        case pdfFileName
    }

    static func == (lhs: PracticeSession, rhs: PracticeSession) -> Bool {
        lhs.id == rhs.id &&
        lhs.completedQuestionIds == rhs.completedQuestionIds &&
        lhs.answers.count == rhs.answers.count &&
        lhs.isOrganized == rhs.isOrganized
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(completedQuestionIds.count)
        hasher.combine(isOrganized)
    }

    init(id: String, questions: [QuestionGenerationService.GeneratedQuestion], generationType: String, subject: String, difficulty: String, questionType: String, createdDate: Date, lastAccessedDate: Date, completedQuestionIds: [String], answers: [String: [String: Any]], isOrganized: Bool = false, pdfFileName: String? = nil) {
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
        self.isOrganized = isOrganized
        self.pdfFileName = pdfFileName
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
        isOrganized = (try? container.decode(Bool.self, forKey: .isOrganized)) ?? false
        pdfFileName = try? container.decode(String.self, forKey: .pdfFileName)

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
        try container.encode(isOrganized, forKey: .isOrganized)
        try? container.encodeIfPresent(pdfFileName, forKey: .pdfFileName)
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
        ZStack(alignment: .topTrailing) {
            // Main card body — same HStack layout as GenerationTypeCard
            HStack(spacing: 16) {
                // LEFT: Icon in colored circle (same as GenerationTypeCard)
                ZStack {
                    Circle()
                        .fill(session.generationTypeColor.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: session.generationTypeIcon)
                        .font(.title2)
                        .foregroundColor(session.generationTypeColor)
                }

                // MIDDLE: Title + subtitle + progress bar
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("questionGeneration.resume.title", comment: ""))
                        .font(.body.bold())
                        .foregroundColor(.primary)

                    Text(String(format: NSLocalizedString("questionGeneration.resume.subtitle", comment: ""), session.localizedGenerationType, session.remainingQuestions))
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(session.generationTypeColor)
                                .frame(width: geometry.size.width * session.progressPercentage, height: 4)
                        }
                    }
                    .frame(height: 4)
                }

                Spacer()

                // RIGHT: Continue button (same side as GenerationTypeCard checkmark)
                Button(action: onResume) {
                    Text(NSLocalizedString("questionGeneration.resume.button", comment: ""))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(session.generationTypeColor)
                        .cornerRadius(8)
                }
            }
            .padding()
            .background(session.generationTypeColor.opacity(0.05))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(session.generationTypeColor.opacity(0.3), lineWidth: 1)
            )

            // TOP-RIGHT: X dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray.opacity(0.7))
                    .background(Color(.systemBackground))
                    .clipShape(Circle())
            }
            .offset(x: 8, y: -8)
        }
    }
}
