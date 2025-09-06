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
    case mathematics = "Mathematics"
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
        case .english: return "textbook"
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
    
    // Auto-detect subject from AI parsing result
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