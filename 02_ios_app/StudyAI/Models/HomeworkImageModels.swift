//
//  HomeworkImageModels.swift
//  StudyAI
//
//  Created by Claude Code on 10/23/25.
//

import Foundation
import SwiftUI

// MARK: - Homework Image Record

/// Represents a saved homework image with metadata
struct HomeworkImageRecord: Codable, Identifiable {
    let id: String
    let imageFileNames: [String]        // ✅ UPDATED: Array of image files for multi-page support
    let thumbnailFileName: String       // Thumbnail for grid view (first page)
    let pageCount: Int                  // ✅ NEW: Number of pages in this homework deck
    let submittedDate: Date             // When it was graded
    let subject: String                 // Auto-detected subject
    let accuracy: Float                 // Performance percentage (0.0 - 1.0)
    let questionCount: Int              // Number of questions
    let imageHash: String?              // SHA256 hash to detect duplicates

    // Optional fields for enhanced display
    let correctCount: Int?              // Number of correct answers
    let incorrectCount: Int?            // Number of incorrect answers
    let totalPoints: Float?             // Total points earned
    let maxPoints: Float?               // Maximum possible points
    let rawQuestions: [String]?         // Raw question texts for PDF generation

    // ✅ NEW: Pro Mode digital homework data (stored as JSON)
    let proModeData: Data?              // Serialized DigitalHomeworkData for Pro Mode homework

    // ✅ Backward compatibility - return first image filename
    var imageFileName: String {
        imageFileNames.first ?? ""
    }

    // ✅ Check if this is a multi-page homework deck
    var isMultiPage: Bool {
        pageCount > 1
    }

    // Custom initializer with default value for imageHash
    init(
        id: String,
        imageFileNames: [String],
        thumbnailFileName: String,
        pageCount: Int,
        submittedDate: Date,
        subject: String,
        accuracy: Float,
        questionCount: Int,
        imageHash: String? = nil,
        correctCount: Int? = nil,
        incorrectCount: Int? = nil,
        totalPoints: Float? = nil,
        maxPoints: Float? = nil,
        rawQuestions: [String]? = nil,
        proModeData: Data? = nil
    ) {
        self.id = id
        self.imageFileNames = imageFileNames
        self.thumbnailFileName = thumbnailFileName
        self.pageCount = pageCount
        self.submittedDate = submittedDate
        self.subject = subject
        self.accuracy = accuracy
        self.questionCount = questionCount
        self.imageHash = imageHash
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.totalPoints = totalPoints
        self.maxPoints = maxPoints
        self.rawQuestions = rawQuestions
        self.proModeData = proModeData
    }

    // ✅ Backward compatibility initializer (for migration from single-image records)
    init(
        id: String,
        imageFileName: String,
        thumbnailFileName: String,
        submittedDate: Date,
        subject: String,
        accuracy: Float,
        questionCount: Int,
        imageHash: String? = nil,
        correctCount: Int? = nil,
        incorrectCount: Int? = nil,
        totalPoints: Float? = nil,
        maxPoints: Float? = nil,
        rawQuestions: [String]? = nil,
        proModeData: Data? = nil
    ) {
        self.id = id
        self.imageFileNames = [imageFileName]
        self.thumbnailFileName = thumbnailFileName
        self.pageCount = 1
        self.submittedDate = submittedDate
        self.subject = subject
        self.accuracy = accuracy
        self.questionCount = questionCount
        self.imageHash = imageHash
        self.correctCount = correctCount
        self.incorrectCount = incorrectCount
        self.totalPoints = totalPoints
        self.maxPoints = maxPoints
        self.rawQuestions = rawQuestions
        self.proModeData = proModeData
    }

    var accuracyPercentage: String {
        return String(format: "%.0f%%", accuracy * 100)
    }

    var scoreText: String? {
        guard let total = totalPoints, let max = maxPoints else { return nil }
        return "\(String(format: "%.1f", total))/\(String(format: "%.1f", max))"
    }

    var accuracyColor: Color {
        if accuracy >= 0.9 {
            return .green
        } else if accuracy >= 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    var subjectIcon: String {
        switch subject.lowercased() {
        case "mathematics", "math":
            return "function"
        case "physics":
            return "atom"
        case "chemistry":
            return "flask.fill"
        case "biology":
            return "leaf.fill"
        case "english", "literature":
            return "book.fill"
        case "history":
            return "building.columns.fill"
        default:
            return "book.closed.fill"
        }
    }

    // ✅ Custom Codable implementation for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id
        case imageFileNames
        case imageFileName  // Old key for backward compatibility
        case thumbnailFileName
        case pageCount
        case submittedDate
        case subject
        case accuracy
        case questionCount
        case imageHash
        case correctCount
        case incorrectCount
        case totalPoints
        case maxPoints
        case rawQuestions
        case proModeData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        thumbnailFileName = try container.decode(String.self, forKey: .thumbnailFileName)
        submittedDate = try container.decode(Date.self, forKey: .submittedDate)
        subject = try container.decode(String.self, forKey: .subject)
        accuracy = try container.decode(Float.self, forKey: .accuracy)
        questionCount = try container.decode(Int.self, forKey: .questionCount)

        // ✅ Backward compatibility: try new format first, fallback to old format
        if let fileNames = try? container.decode([String].self, forKey: .imageFileNames) {
            imageFileNames = fileNames
            pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? fileNames.count
        } else if let fileName = try? container.decode(String.self, forKey: .imageFileName) {
            // Old format: single imageFileName
            imageFileNames = [fileName]
            pageCount = 1
        } else {
            throw DecodingError.dataCorruptedError(forKey: .imageFileNames, in: container, debugDescription: "Missing both imageFileNames and imageFileName")
        }

        imageHash = try container.decodeIfPresent(String.self, forKey: .imageHash)
        correctCount = try container.decodeIfPresent(Int.self, forKey: .correctCount)
        incorrectCount = try container.decodeIfPresent(Int.self, forKey: .incorrectCount)
        totalPoints = try container.decodeIfPresent(Float.self, forKey: .totalPoints)
        maxPoints = try container.decodeIfPresent(Float.self, forKey: .maxPoints)
        rawQuestions = try container.decodeIfPresent([String].self, forKey: .rawQuestions)
        proModeData = try container.decodeIfPresent(Data.self, forKey: .proModeData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(imageFileNames, forKey: .imageFileNames)
        try container.encode(thumbnailFileName, forKey: .thumbnailFileName)
        try container.encode(pageCount, forKey: .pageCount)
        try container.encode(submittedDate, forKey: .submittedDate)
        try container.encode(subject, forKey: .subject)
        try container.encode(accuracy, forKey: .accuracy)
        try container.encode(questionCount, forKey: .questionCount)
        try container.encodeIfPresent(imageHash, forKey: .imageHash)
        try container.encodeIfPresent(correctCount, forKey: .correctCount)
        try container.encodeIfPresent(incorrectCount, forKey: .incorrectCount)
        try container.encodeIfPresent(totalPoints, forKey: .totalPoints)
        try container.encodeIfPresent(maxPoints, forKey: .maxPoints)
        try container.encodeIfPresent(rawQuestions, forKey: .rawQuestions)
        try container.encodeIfPresent(proModeData, forKey: .proModeData)
    }
}

// MARK: - Time Filter Enum

enum HomeworkTimeFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case allTime = "All Time"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .today: return "calendar.badge.clock"
        case .thisWeek: return "calendar"
        case .thisMonth: return "calendar.circle"
        case .allTime: return "clock"
        }
    }
}

// MARK: - Subject Filter Enum

enum HomeworkSubjectFilter: String, CaseIterable, Identifiable {
    case all = "All Subjects"
    case mathematics = "Math"
    case physics = "Physics"
    case chemistry = "Chemistry"
    case biology = "Biology"
    case english = "English"
    case history = "History"
    case other = "Other"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .mathematics: return "function"
        case .physics: return "atom"
        case .chemistry: return "flask.fill"
        case .biology: return "leaf.fill"
        case .english: return "book.fill"
        case .history: return "building.columns.fill"
        case .other: return "book.closed.fill"
        }
    }
}

// MARK: - Grade Filter Enum

enum HomeworkGradeFilter: String, CaseIterable, Identifiable {
    case all = "All Grades"
    case excellent = "Excellent (≥90%)"
    case good = "Good (≥70%)"
    case needsPractice = "Needs Practice (<70%)"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .all: return "star"
        case .excellent: return "star.fill"
        case .good: return "star.leadinghalf.filled"
        case .needsPractice: return "arrow.triangle.2.circlepath"
        }
    }

    func matches(accuracy: Float) -> Bool {
        switch self {
        case .all:
            return true
        case .excellent:
            return accuracy >= 0.9
        case .good:
            return accuracy >= 0.7 && accuracy < 0.9
        case .needsPractice:
            return accuracy < 0.7
        }
    }
}
