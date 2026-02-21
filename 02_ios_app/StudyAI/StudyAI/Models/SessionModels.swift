//
//  SessionModels.swift
//  StudyAI
//
//  Created by Claude Code on 9/4/25.
//

import Foundation

// MARK: - Session Archive Models

struct ArchivedSession: Codable, Identifiable {
    let id: String
    let userId: String
    let subject: String
    let sessionDate: Date
    let title: String?
    
    // Image storage
    let originalImageUrl: String
    let thumbnailUrl: String?
    
    // AI parsing results
    let aiParsingResult: HomeworkParsingResult
    let processingTime: Double
    let overallConfidence: Float
    
    // Student interaction
    let studentAnswers: [String: String]?
    let notes: String?
    let reviewCount: Int
    let lastReviewedAt: Date?
    
    // Metadata
    let createdAt: Date
    let updatedAt: Date
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        subject: String,
        sessionDate: Date = Date(),
        title: String? = nil,
        originalImageUrl: String,
        thumbnailUrl: String? = nil,
        aiParsingResult: HomeworkParsingResult,
        processingTime: Double,
        overallConfidence: Float,
        studentAnswers: [String: String]? = nil,
        notes: String? = nil,
        reviewCount: Int = 0,
        lastReviewedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.subject = subject
        self.sessionDate = sessionDate
        self.title = title
        self.originalImageUrl = originalImageUrl
        self.thumbnailUrl = thumbnailUrl
        self.aiParsingResult = aiParsingResult
        self.processingTime = processingTime
        self.overallConfidence = overallConfidence
        self.studentAnswers = studentAnswers
        self.notes = notes
        self.reviewCount = reviewCount
        self.lastReviewedAt = lastReviewedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Session Summary for List Display

struct SessionSummary: Codable, Identifiable {
    let id: String
    let subject: String
    let sessionDate: Date
    let title: String
    let questionCount: Int
    let overallConfidence: Float
    let thumbnailUrl: String?
    let reviewCount: Int
    
    init(from archivedSession: ArchivedSession) {
        self.id = archivedSession.id
        self.subject = archivedSession.subject
        self.sessionDate = archivedSession.sessionDate
        self.title = archivedSession.title ?? "Homework Session"
        self.questionCount = archivedSession.aiParsingResult.questionCount
        self.overallConfidence = archivedSession.overallConfidence
        self.thumbnailUrl = archivedSession.thumbnailUrl
        self.reviewCount = archivedSession.reviewCount
    }
    
    init(
        id: String,
        subject: String,
        sessionDate: Date,
        title: String,
        questionCount: Int,
        overallConfidence: Float,
        thumbnailUrl: String?,
        reviewCount: Int
    ) {
        self.id = id
        self.subject = subject
        self.sessionDate = sessionDate
        self.title = title
        self.questionCount = questionCount
        self.overallConfidence = overallConfidence
        self.thumbnailUrl = thumbnailUrl
        self.reviewCount = reviewCount
    }
}

// MARK: - Archive Request Models

struct ArchiveSessionRequest {
    let homeworkResult: HomeworkParsingResult
    let originalImageUrl: String
    let subject: String
    let studentAnswers: [String: String]?
    let notes: String?
    
    init(
        homeworkResult: HomeworkParsingResult,
        originalImageUrl: String,
        subject: String,
        studentAnswers: [String: String]? = nil,
        notes: String? = nil
    ) {
        self.homeworkResult = homeworkResult
        self.originalImageUrl = originalImageUrl
        self.subject = subject
        self.studentAnswers = studentAnswers
        self.notes = notes
    }
}

// MARK: - Subject Categories

enum SubjectCategory: String, CaseIterable, Codable {
    case mathematics = "Math"
    case physics = "Physics"
    case chemistry = "Chemistry"
    case biology = "Biology"
    case english = "English"
    case history = "History"
    case geography = "Geography"
    case computerScience = "Computer Science"
    case foreignLanguage = "Foreign Language"
    case arts = "Arts"
    case other = "Other"
    
    var icon: String {
        switch self {
        case .mathematics: return "function"
        case .physics: return "atom"
        case .chemistry: return "flask"
        case .biology: return "leaf"
        case .english: return "book.pages"
        case .history: return "clock.arrow.circlepath"
        case .geography: return "globe"
        case .computerScience: return "laptopcomputer"
        case .foreignLanguage: return "globe.badge.chevron.backward"
        case .arts: return "paintbrush"
        case .other: return "book"
        }
    }
    
    var color: String {
        switch self {
        case .mathematics: return "blue"
        case .physics: return "purple"
        case .chemistry: return "green"
        case .biology: return "orange"
        case .english: return "red"
        case .history: return "brown"
        case .geography: return "teal"
        case .computerScience: return "indigo"
        case .foreignLanguage: return "pink"
        case .arts: return "yellow"
        case .other: return "gray"
        }
    }
    
    var displayName: String {
        return self.rawValue
    }
    
    static func detectSubject(from result: HomeworkParsingResult) -> SubjectCategory {
        let content = result.questions.map { $0.questionText + " " + $0.answerText }.joined().lowercased()
        
        // Math-related keywords
        if content.contains("equation") || content.contains("solve") || content.contains("calculate") || 
           content.contains("derivative") || content.contains("integral") || content.contains("algebra") ||
           content.contains("geometry") || content.contains("trigonometry") {
            return .mathematics
        }
        
        // Physics keywords
        if content.contains("force") || content.contains("velocity") || content.contains("acceleration") ||
           content.contains("energy") || content.contains("momentum") || content.contains("wave") {
            return .physics
        }
        
        // Chemistry keywords
        if content.contains("molecule") || content.contains("atom") || content.contains("reaction") ||
           content.contains("chemical") || content.contains("compound") || content.contains("element") {
            return .chemistry
        }
        
        // Biology keywords
        if content.contains("cell") || content.contains("dna") || content.contains("organism") ||
           content.contains("evolution") || content.contains("ecosystem") || content.contains("protein") {
            return .biology
        }
        
        // English/Literature keywords
        if content.contains("literature") || content.contains("poem") || content.contains("author") ||
           content.contains("character") || content.contains("theme") || content.contains("essay") {
            return .english
        }
        
        // History keywords
        if content.contains("war") || content.contains("revolution") || content.contains("century") ||
           content.contains("ancient") || content.contains("empire") || content.contains("civilization") {
            return .history
        }

        return .other
    }

    /// Convert string to SubjectCategory (case-insensitive matching)
    static func fromString(_ string: String) -> SubjectCategory? {
        let lowercased = string.lowercased()

        // Try exact match first
        if let category = SubjectCategory.allCases.first(where: { $0.rawValue.lowercased() == lowercased }) {
            return category
        }

        // Try partial match for common variations
        if lowercased.contains("math") {
            return .mathematics
        } else if lowercased.contains("physic") {
            return .physics
        } else if lowercased.contains("chem") {
            return .chemistry
        } else if lowercased.contains("bio") {
            return .biology
        } else if lowercased.contains("english") || lowercased.contains("literature") {
            return .english
        } else if lowercased.contains("history") {
            return .history
        } else if lowercased.contains("geography") || lowercased.contains("geo") {
            return .geography
        } else if lowercased.contains("computer") || lowercased.contains("programming") || lowercased.contains("coding") {
            return .computerScience
        } else if lowercased.contains("language") && !lowercased.contains("english") {
            return .foreignLanguage
        } else if lowercased.contains("art") || lowercased.contains("music") || lowercased.contains("drama") {
            return .arts
        }

        return .other
    }
}

// MARK: - Archived Conversation Models

// Behavior Summary for parent reports
struct BehaviorSummary: Codable {
    let frustrationLevel: Int              // 0-5
    let hasRedFlags: Bool
    let engagementScore: Double            // 0.0-1.0
    let curiosityCount: Int?               // Optional: Number of curiosity indicators

    enum CodingKeys: String, CodingKey {
        case frustrationLevel, hasRedFlags, engagementScore, curiosityCount
    }
}

struct ArchivedConversation: Codable, Identifiable {
    let id: String
    let userId: String
    let subject: String
    let topic: String?
    let conversationContent: String
    let archivedDate: Date
    let createdAt: Date
    let diagrams: [[String: Any]]?  // ✅ EXISTING: Store diagram data
    let voiceAudioFiles: [String: String]?  // msgIndex → file path (Live mode only)

    // ✅ NEW: AI-generated summary and analysis fields
    let summary: String?                    // AI-generated summary (50-100 chars)
    let keyTopics: [String]?               // Key topics discussed
    let learningOutcomes: [String]?        // Learning outcomes achieved
    let estimatedDuration: Int?            // Session duration in minutes
    let behaviorSummary: BehaviorSummary?  // Behavior insights

    enum CodingKeys: String, CodingKey {
        case id, userId, subject, topic, conversationContent, archivedDate, createdAt, diagrams
        case voiceAudioFiles
        case summary, keyTopics, learningOutcomes, estimatedDuration, behaviorSummary
    }

    init(id: String, userId: String, subject: String, topic: String?, conversationContent: String, archivedDate: Date, createdAt: Date, diagrams: [[String: Any]]? = nil, voiceAudioFiles: [String: String]? = nil, summary: String? = nil, keyTopics: [String]? = nil, learningOutcomes: [String]? = nil, estimatedDuration: Int? = nil, behaviorSummary: BehaviorSummary? = nil) {
        self.id = id
        self.userId = userId
        self.subject = subject
        self.topic = topic
        self.conversationContent = conversationContent
        self.archivedDate = archivedDate
        self.createdAt = createdAt
        self.diagrams = diagrams
        self.voiceAudioFiles = voiceAudioFiles
        self.summary = summary
        self.keyTopics = keyTopics
        self.learningOutcomes = learningOutcomes
        self.estimatedDuration = estimatedDuration
        self.behaviorSummary = behaviorSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        subject = try container.decode(String.self, forKey: .subject)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        conversationContent = try container.decode(String.self, forKey: .conversationContent)
        archivedDate = try container.decode(Date.self, forKey: .archivedDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        // Decode diagrams as [[String: Any]]
        if let diagramsData = try? container.decodeIfPresent(Data.self, forKey: .diagrams) {
            diagrams = try? JSONSerialization.jsonObject(with: diagramsData) as? [[String: Any]]
        } else {
            diagrams = nil
        }

        voiceAudioFiles = try container.decodeIfPresent([String: String].self, forKey: .voiceAudioFiles)

        // NEW: Decode summary fields
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        keyTopics = try container.decodeIfPresent([String].self, forKey: .keyTopics)
        learningOutcomes = try container.decodeIfPresent([String].self, forKey: .learningOutcomes)
        estimatedDuration = try container.decodeIfPresent(Int.self, forKey: .estimatedDuration)
        behaviorSummary = try container.decodeIfPresent(BehaviorSummary.self, forKey: .behaviorSummary)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(topic, forKey: .topic)
        try container.encode(conversationContent, forKey: .conversationContent)
        try container.encode(archivedDate, forKey: .archivedDate)
        try container.encode(createdAt, forKey: .createdAt)

        // Encode diagrams
        if let diagrams = diagrams {
            let diagramsData = try? JSONSerialization.data(withJSONObject: diagrams)
            try container.encodeIfPresent(diagramsData, forKey: .diagrams)
        }

        try container.encodeIfPresent(voiceAudioFiles, forKey: .voiceAudioFiles)

        // NEW: Encode summary fields
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(keyTopics, forKey: .keyTopics)
        try container.encodeIfPresent(learningOutcomes, forKey: .learningOutcomes)
        try container.encodeIfPresent(estimatedDuration, forKey: .estimatedDuration)
        try container.encodeIfPresent(behaviorSummary, forKey: .behaviorSummary)
    }
}

// MARK: - Statistics Models

struct ArchiveStatistics {
    let totalSessions: Int
    let totalQuestions: Int
    let averageConfidence: Float
    let mostStudiedSubject: SubjectCategory?
    let streakDays: Int
    let thisWeekSessions: Int
    let thisMonthSessions: Int
    let subjectBreakdown: [SubjectCategory: Int]
}