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
    let imageFileName: String           // Local file path in Documents
    let thumbnailFileName: String       // Thumbnail for grid view
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

    // Custom initializer with default value for imageHash
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
        rawQuestions: [String]? = nil
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.thumbnailFileName = thumbnailFileName
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
    case mathematics = "Mathematics"
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
