//
//  MistakeReviewService.swift
//  StudyAI
//
//  Created by Claude Code on 9/20/25.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class MistakeReviewService: ObservableObject {
    @Published var isLoading = false
    @Published var subjectsWithMistakes: [SubjectMistakeCount] = []
    @Published var mistakes: [MistakeQuestion] = []
    @Published var errorMessage: String?

    private let questionLocalStorage = QuestionLocalStorage.shared

    /// Fetch subjects with mistake counts from LOCAL STORAGE ONLY
    func fetchSubjectsWithMistakes(timeRange: MistakeTimeRange? = nil) async {
        print("🔍 [MistakeReview] === FETCHING SUBJECTS FROM LOCAL STORAGE ===")
        print("🔍 [MistakeReview] Time range: \(timeRange?.rawValue ?? "All Time")")

        isLoading = true
        errorMessage = nil

        // ✅ Fetch from local storage only
        let allMistakes = questionLocalStorage.getMistakeQuestions()

        // ✅ Filter by time range
        let filteredMistakes = filterByTimeRange(allMistakes, timeRange: timeRange)

        // Group by subject and count
        var subjectCounts: [String: Int] = [:]
        for mistake in filteredMistakes {
            if let subject = mistake["subject"] as? String {
                subjectCounts[subject, default: 0] += 1
            }
        }

        // Convert to SubjectMistakeCount
        let subjects = subjectCounts.map { item in
            SubjectMistakeCount(
                subject: item.key,
                mistakeCount: item.value,
                icon: getSubjectIcon(item.key)
            )
        }.sorted { $0.mistakeCount > $1.mistakeCount } // Sort by count descending

        print("✅ [MistakeReview] Successfully fetched subjects from local storage")
        print("📊 [MistakeReview] Found \(subjects.count) subjects with mistakes in time range:")
        for subject in subjects {
            print("   - \(subject.subject): \(subject.mistakeCount) mistakes")
        }

        self.subjectsWithMistakes = subjects
        isLoading = false
        print("🔍 [MistakeReview] === FETCH SUBJECTS COMPLETE ===\n")
    }

    /// Fetch mistakes from LOCAL STORAGE ONLY
    func fetchMistakes(subject: String?, timeRange: MistakeTimeRange) async {
        print("🔍 [MistakeReview] === FETCHING MISTAKES FROM LOCAL STORAGE ===")
        print("🔍 [MistakeReview] Subject: \(subject ?? "All Subjects")")
        print("🔍 [MistakeReview] Time range: \(timeRange.rawValue)")

        isLoading = true
        errorMessage = nil

        // ✅ Fetch from local storage only
        let allMistakeData = questionLocalStorage.getMistakeQuestions(subject: subject)

        // ✅ Filter by time range
        let filteredMistakeData = filterByTimeRange(allMistakeData, timeRange: timeRange == .allTime ? nil : timeRange)

        // Convert to MistakeQuestion format
        var mistakes: [MistakeQuestion] = []
        for data in filteredMistakeData {
            if let id = data["id"] as? String,
               let subject = data["subject"] as? String,
               let questionText = data["questionText"] as? String,
               let answerText = data["answerText"] as? String {

                let studentAnswer = data["studentAnswer"] as? String ?? ""
                let feedback = data["feedback"] as? String ?? ""
                let archivedAtString = data["archivedAt"] as? String ?? ""

                // ✅ Extract rawQuestionText (full original question from image)
                let rawQuestionText = data["rawQuestionText"] as? String ?? questionText

                // Parse date from archivedAt string
                let dateFormatter = ISO8601DateFormatter()
                let createdAt = dateFormatter.date(from: archivedAtString) ?? Date()

                // Extract grading data
                let points = (data["points"] as? Float).map(Double.init) ?? 0.0
                let maxPoints = (data["maxPoints"] as? Float).map(Double.init) ?? 1.0
                let confidence = (data["confidence"] as? Float).map(Double.init) ?? 0.0
                let tags = data["tags"] as? [String] ?? []
                let notes = data["notes"] as? String ?? ""

                let mistake = MistakeQuestion(
                    id: id,
                    subject: subject,
                    question: questionText,
                    rawQuestionText: rawQuestionText,  // ✅ Pass full question text
                    correctAnswer: answerText,
                    studentAnswer: studentAnswer,
                    explanation: feedback,
                    createdAt: createdAt,
                    confidence: confidence,
                    pointsEarned: points,
                    pointsPossible: maxPoints,
                    tags: tags,
                    notes: notes
                )
                mistakes.append(mistake)
            }
        }

        print("✅ [MistakeReview] Successfully fetched mistakes from local storage")
        print("📊 [MistakeReview] Total mistakes retrieved: \(mistakes.count)")

        if mistakes.isEmpty {
            print("⚠️ [MistakeReview] No mistakes found in local storage")
        } else {
            print("📋 [MistakeReview] Mistake summary:")
            for (index, mistake) in mistakes.prefix(5).enumerated() {
                print("   \(index + 1). [\(mistake.subject)] \(mistake.question.prefix(50))...")
                print("      Student: \(mistake.studentAnswer.prefix(30))...")
                print("      Correct: \(mistake.correctAnswer.prefix(30))...")
            }
            if mistakes.count > 5 {
                print("   ... and \(mistakes.count - 5) more")
            }
        }

        self.mistakes = mistakes
        isLoading = false
        print("🔍 [MistakeReview] === FETCH MISTAKES COMPLETE ===\n")
    }

    /// Get mistake statistics from LOCAL STORAGE ONLY
    func getMistakeStats() async -> MistakeStats? {
        print("🔍 [MistakeReview] === FETCHING STATS FROM LOCAL STORAGE ===")

        let allMistakes = questionLocalStorage.getMistakeQuestions()
        let subjectData = questionLocalStorage.getSubjectsWithMistakes()

        // ✅ Calculate time-based statistics with filtering
        let mistakesLastWeek = filterByTimeRange(allMistakes, timeRange: .thisWeek).count
        let mistakesLastMonth = filterByTimeRange(allMistakes, timeRange: .thisMonth).count

        let stats = MistakeStats(
            totalMistakes: allMistakes.count,
            subjectsWithMistakes: subjectData.count,
            mistakesLastWeek: mistakesLastWeek,
            mistakesLastMonth: mistakesLastMonth
        )

        print("✅ [MistakeReview] Successfully calculated stats from local storage")
        print("📊 [MistakeReview] Stats summary:")
        print("   - Total mistakes: \(stats.totalMistakes)")
        print("   - Subjects with mistakes: \(stats.subjectsWithMistakes)")
        print("   - Mistakes last week: \(stats.mistakesLastWeek)")
        print("   - Mistakes last month: \(stats.mistakesLastMonth)")

        print("🔍 [MistakeReview] === FETCH STATS COMPLETE ===\n")
        return stats
    }

    /// Filter mistakes by time range
    private func filterByTimeRange(_ mistakes: [[String: Any]], timeRange: MistakeTimeRange?) -> [[String: Any]] {
        guard let timeRange = timeRange else {
            // No time range specified, return all
            print("🔍 [MistakeReview] No time range filter - returning all \(mistakes.count) mistakes")
            return mistakes
        }

        let now = Date()
        let calendar = Calendar.current

        let cutoffDate: Date
        switch timeRange {
        case .thisWeek:
            // Last 7 days
            cutoffDate = calendar.date(byAdding: .day, value: -7, to: now)!
            print("🔍 [MistakeReview] Filtering for THIS WEEK (last 7 days)")
        case .thisMonth:
            // Last 30 days
            cutoffDate = calendar.date(byAdding: .day, value: -30, to: now)!
            print("🔍 [MistakeReview] Filtering for THIS MONTH (last 30 days)")
        case .allTime:
            // Return all mistakes
            print("🔍 [MistakeReview] ALL TIME selected - returning all \(mistakes.count) mistakes")
            return mistakes
        }

        print("🔍 [MistakeReview] Now: \(now)")
        print("🔍 [MistakeReview] Cutoff date: \(cutoffDate)")
        print("🔍 [MistakeReview] Total mistakes to check: \(mistakes.count)")

        // Filter mistakes by archived date
        var parsedDatesCount = 0
        var failedParseCount = 0
        var matchingCount = 0

        let filtered = mistakes.filter { mistake in
            // Debug: Print first few mistakes in detail
            if parsedDatesCount + failedParseCount < 5 {
                print("🔍 [MistakeReview] Checking mistake: subject=\(mistake["subject"] as? String ?? "N/A"), archivedAt=\(mistake["archivedAt"] as? String ?? "MISSING")")
            }

            guard let archivedAtString = mistake["archivedAt"] as? String else {
                failedParseCount += 1
                if failedParseCount <= 3 {
                    print("⚠️ [MistakeReview] Missing archivedAt field in mistake")
                }
                return false
            }

            let dateFormatter = ISO8601DateFormatter()
            guard let mistakeDate = dateFormatter.date(from: archivedAtString) else {
                failedParseCount += 1
                if failedParseCount <= 3 {
                    print("⚠️ [MistakeReview] Failed to parse date: \(archivedAtString)")
                }
                return false
            }

            parsedDatesCount += 1
            let matches = mistakeDate >= cutoffDate
            if matches {
                matchingCount += 1
            }

            // Log first few comparisons
            if parsedDatesCount <= 5 {
                print("🔍 [MistakeReview] Mistake date: \(mistakeDate), matches: \(matches)")
            }

            return matches
        }

        print("📊 [MistakeReview] Time filter results:")
        print("   - Time range: \(timeRange.rawValue)")
        print("   - Total mistakes checked: \(mistakes.count)")
        print("   - Successfully parsed dates: \(parsedDatesCount)")
        print("   - Failed to parse: \(failedParseCount)")
        print("   - Matching date range: \(matchingCount)")
        print("   - Final filtered count: \(filtered.count)")

        return filtered
    }

    /// Get icon for subject (uses SF Symbols compatible with Image(systemName:))
    private func getSubjectIcon(_ subject: String) -> String {
        // Normalize subject first to handle "Math"/"Mathematics" variants
        let normalized = QuestionSummary.normalizeSubject(subject)

        switch normalized {
        case "Math": return "function"  // SF Symbol for mathematical function
        case "Physics": return "atom"  // SF Symbol for atom
        case "Chemistry": return "flask.fill"  // SF Symbol for flask
        case "Biology": return "leaf.fill"  // SF Symbol for biology/nature
        case "English": return "book.fill"  // SF Symbol for books
        case "History": return "clock.fill"  // SF Symbol for history/time
        case "Geography": return "globe"  // SF Symbol for globe
        case "Computer Science": return "desktopcomputer"  // SF Symbol for computer
        case "Science": return "lightbulb.fill"  // SF Symbol for science/ideas
        default: return "book.closed.fill"  // SF Symbol for general subject
        }
    }
}