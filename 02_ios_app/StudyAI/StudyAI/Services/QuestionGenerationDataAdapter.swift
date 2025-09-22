//
//  QuestionGenerationDataAdapter.swift
//  StudyAI
//
//  Created by Claude Code on 12/21/24.
//

import Foundation

/// Service adapter that converts existing app data into formats suitable for question generation
class QuestionGenerationDataAdapter {
    static let shared = QuestionGenerationDataAdapter()

    private init() {}

    // MARK: - User Profile Conversion

    /// Create a user profile from available app data
    func createUserProfile() -> QuestionGenerationService.UserProfile {
        // Get user profile data from ProfileService if available
        let profileService = ProfileService.shared

        let grade = profileService.currentProfile?.gradeLevel ?? "High School"
        let location = profileService.currentProfile?.displayLocation ?? "US"

        // Create preferences based on user's activity
        var preferences: [String: Any] = [:]

        // Add learning preferences if we can determine them
        preferences["preferred_question_types"] = ["multiple_choice", "short_answer"]
        preferences["difficulty_preference"] = "adaptive"
        preferences["subject_interests"] = profileService.currentProfile?.favoriteSubjects ?? ["Mathematics", "Science"]

        return QuestionGenerationService.UserProfile(
            grade: grade,
            location: location,
            preferences: preferences
        )
    }

    // MARK: - Basic Configuration Methods

    /// Get recommended question count based on default settings
    func getRecommendedQuestionCount() -> Int {
        return 5
    }

    /// Get overall difficulty recommendation based on default settings
    func getRecommendedDifficulty() -> QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty {
        return .intermediate
    }

    /// Get default focus areas
    func getFocusAreas() -> [String] {
        return ["Mathematics", "Science", "General"]
    }

    /// Get common subjects for selection
    func getMostCommonSubjects() -> [String] {
        return ["Mathematics", "Science", "Physics", "Chemistry", "Biology", "English"]
    }
}