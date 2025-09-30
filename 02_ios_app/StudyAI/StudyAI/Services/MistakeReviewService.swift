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
        isLoading = true
        errorMessage = nil

        do {
            let subjects = try await networkService.getMistakeSubjects(timeRange: timeRange?.apiValue)
            self.subjectsWithMistakes = subjects
        } catch {
            self.errorMessage = error.localizedDescription
            self.subjectsWithMistakes = []

        }

        isLoading = false
    }

    func fetchMistakes(subject: String?, timeRange: MistakeTimeRange) async {
        isLoading = true
        errorMessage = nil

        do {
            let mistakes = try await networkService.getMistakes(
                subject: subject,
                timeRange: timeRange.apiValue
            )
            self.mistakes = mistakes
        } catch {
            self.errorMessage = error.localizedDescription
            self.mistakes = []

        }

        isLoading = false
    }

    func getMistakeStats() async -> MistakeStats? {
        do {
            return try await networkService.getMistakeStats()
        } catch {

            return nil
        }
    }
}