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

    private let networkService = NetworkService.shared

    func fetchSubjectsWithMistakes(timeRange: MistakeTimeRange? = nil) async {
        print("🔍 [MistakeReview] === FETCHING SUBJECTS WITH MISTAKES ===")
        print("🔍 [MistakeReview] Time range: \(timeRange?.rawValue ?? "All Time")")

        isLoading = true
        errorMessage = nil

        do {
            let subjects = try await networkService.getMistakeSubjects(timeRange: timeRange?.apiValue)

            print("✅ [MistakeReview] Successfully fetched subjects")
            print("📊 [MistakeReview] Found \(subjects.count) subjects with mistakes:")
            for subject in subjects {
                print("   - \(subject.subject): \(subject.mistakeCount) mistakes")
            }

            self.subjectsWithMistakes = subjects
        } catch {
            print("❌ [MistakeReview] Failed to fetch subjects: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.subjectsWithMistakes = []
        }

        isLoading = false
        print("🔍 [MistakeReview] === FETCH SUBJECTS COMPLETE ===\n")
    }

    func fetchMistakes(subject: String?, timeRange: MistakeTimeRange) async {
        print("🔍 [MistakeReview] === FETCHING MISTAKES ===")
        print("🔍 [MistakeReview] Subject: \(subject ?? "All Subjects")")
        print("🔍 [MistakeReview] Time range: \(timeRange.rawValue) (\(timeRange.apiValue))")

        isLoading = true
        errorMessage = nil

        do {
            let mistakes = try await networkService.getMistakes(
                subject: subject,
                timeRange: timeRange.apiValue
            )

            print("✅ [MistakeReview] Successfully fetched mistakes")
            print("📊 [MistakeReview] Total mistakes retrieved: \(mistakes.count)")

            if mistakes.isEmpty {
                print("⚠️ [MistakeReview] No mistakes found for the given criteria")
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
        } catch {
            print("❌ [MistakeReview] Failed to fetch mistakes: \(error.localizedDescription)")
            print("❌ [MistakeReview] Error details: \(error)")
            self.errorMessage = error.localizedDescription
            self.mistakes = []
        }

        isLoading = false
        print("🔍 [MistakeReview] === FETCH MISTAKES COMPLETE ===\n")
    }

    func getMistakeStats() async -> MistakeStats? {
        print("🔍 [MistakeReview] === FETCHING MISTAKE STATS ===")

        do {
            let stats = try await networkService.getMistakeStats()

            print("✅ [MistakeReview] Successfully fetched stats")
            print("📊 [MistakeReview] Stats summary:")
            print("   - Total mistakes: \(stats.totalMistakes)")
            print("   - Subjects with mistakes: \(stats.subjectsWithMistakes)")
            print("   - Mistakes last week: \(stats.mistakesLastWeek)")
            print("   - Mistakes last month: \(stats.mistakesLastMonth)")

            print("🔍 [MistakeReview] === FETCH STATS COMPLETE ===\n")
            return stats
        } catch {
            print("❌ [MistakeReview] Failed to fetch stats: \(error.localizedDescription)")
            print("🔍 [MistakeReview] === FETCH STATS COMPLETE ===\n")
            return nil
        }
    }
}