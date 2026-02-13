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
        return [
            NSLocalizedString("subject.mathematics", comment: ""),
            NSLocalizedString("subject.science", comment: ""),
            NSLocalizedString("subject.physics", comment: ""),
            NSLocalizedString("subject.chemistry", comment: ""),
            NSLocalizedString("subject.biology", comment: ""),
            NSLocalizedString("subject.english", comment: ""),
            NSLocalizedString("subject.history", comment: ""),
            NSLocalizedString("subject.geography", comment: ""),
            NSLocalizedString("subject.computerScience", comment: ""),
            NSLocalizedString("subject.literature", comment: ""),
            NSLocalizedString("subject.socialStudies", comment: ""),
            NSLocalizedString("subject.economics", comment: ""),
            NSLocalizedString("subject.art", comment: ""),
            NSLocalizedString("subject.music", comment: ""),
            NSLocalizedString("subject.other", comment: "")
        ]
    }

    // MARK: - Personalized Data from Short-Term Status

    /// Extract weakness topics for a specific subject from short-term status
    func getWeaknessTopics(for subject: String) -> [String] {
        let statusService = ShortTermStatusService.shared
        let weaknesses = statusService.status.activeWeaknesses

        print("🔍 [Adapter] Analyzing short-term status for subject: \(subject)")
        print("   Total active weaknesses: \(weaknesses.count)")

        // Filter by subject and extract base branches (prioritize high-value weaknesses)
        let subjectWeaknesses = weaknesses
            .filter { key, value in
                let components = key.split(separator: "/").map(String.init)
                guard let weaknessSubject = components.first else { return false }

                // Match subject and only include actual weaknesses (value > 0)
                return weaknessSubject.lowercased() == subject.lowercased() && value.value > 0
            }
            .sorted { $0.value.value > $1.value.value }  // Sort by weakness severity

        print("   Subject-specific weaknesses (value > 0): \(subjectWeaknesses.count)")

        // Extract unique base branches (main topic areas)
        var baseBranches: [String] = []
        for (key, weakness) in subjectWeaknesses.prefix(10) {  // Top 10 weaknesses
            let components = key.split(separator: "/").map(String.init)
            if components.count >= 2 {
                let baseBranch = components[1]
                if !baseBranches.contains(baseBranch) {
                    baseBranches.append(baseBranch)
                    print("      - \(baseBranch) (severity: \(String(format: "%.2f", weakness.value)))")
                }
            }
        }

        // If no weaknesses found, return general subject
        let result = baseBranches.isEmpty ? [subject] : baseBranches
        print("   ✅ Extracted weakness topics: \(result)")
        return result
    }

    /// Build personalized focus notes from short-term status
    func getPersonalizedFocusNotes(for subject: String) -> String {
        let statusService = ShortTermStatusService.shared
        let weaknesses = statusService.status.activeWeaknesses

        // Filter by subject
        let subjectWeaknesses = weaknesses
            .filter { key, value in
                let components = key.split(separator: "/").map(String.init)
                guard let weaknessSubject = components.first else { return false }
                return weaknessSubject.lowercased() == subject.lowercased() && value.value > 0
            }
            .sorted { $0.value.value > $1.value.value }

        if subjectWeaknesses.isEmpty {
            return "Generate diverse practice questions to build foundational knowledge"
        }

        // Extract detailed branches (specific topics) and error types
        var detailedTopics: [String] = []
        var errorTypes: Set<String> = []

        for (key, value) in subjectWeaknesses.prefix(5) {  // Top 5 weaknesses
            let components = key.split(separator: "/").map(String.init)
            if components.count >= 3 {
                detailedTopics.append(components[2])  // Detailed branch
            }

            // Collect error types
            errorTypes.formUnion(value.recentErrorTypes)
        }

        // Build focus notes
        var notes = "Focus on student's recent struggles:\n"
        notes += "- Weak areas: \(detailedTopics.prefix(3).joined(separator: ", "))\n"

        if errorTypes.contains("conceptual_gap") {
            notes += "- Address conceptual understanding gaps\n"
        }
        if errorTypes.contains("execution_error") {
            notes += "- Practice correct execution and calculation steps\n"
        }
        if errorTypes.contains("needs_refinement") {
            notes += "- Build confidence through repetition\n"
        }

        print("📝 [Adapter] Generated personalized focus notes:")
        print(notes)

        return notes
    }

    /// Get recommended difficulty based on recent performance
    func getAdaptiveDifficulty(for subject: String) -> QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty {
        let statusService = ShortTermStatusService.shared
        let weaknesses = statusService.status.activeWeaknesses

        // Calculate average accuracy for this subject
        let subjectWeaknesses = weaknesses.filter { key, _ in
            let components = key.split(separator: "/").map(String.init)
            guard let weaknessSubject = components.first else { return false }
            return weaknessSubject.lowercased() == subject.lowercased()
        }

        if subjectWeaknesses.isEmpty {
            print("📊 [Adapter] No performance data - using intermediate difficulty")
            return .intermediate  // Default
        }

        let totalAttempts = subjectWeaknesses.values.reduce(0) { $0 + $1.totalAttempts }
        let totalCorrect = subjectWeaknesses.values.reduce(0) { $0 + $1.correctAttempts }

        guard totalAttempts > 0 else {
            print("📊 [Adapter] No attempts recorded - using intermediate difficulty")
            return .intermediate
        }

        let accuracy = Double(totalCorrect) / Double(totalAttempts)

        print("📊 [Adapter] Performance analysis:")
        print("   Total attempts: \(totalAttempts)")
        print("   Correct: \(totalCorrect)")
        print("   Accuracy: \(String(format: "%.1f%%", accuracy * 100))")

        // Adaptive difficulty based on accuracy
        let difficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty
        if accuracy < 0.5 {
            difficulty = .beginner  // Struggling - make it easier
            print("   → Recommendation: BEGINNER (struggling)")
        } else if accuracy < 0.75 {
            difficulty = .intermediate  // Still learning
            print("   → Recommendation: INTERMEDIATE (learning)")
        } else {
            difficulty = .advanced  // Strong performance - challenge them
            print("   → Recommendation: ADVANCED (strong)")
        }

        return difficulty
    }

    /// Mix in mastery topics for confidence building (20% of topics)
    func getMixedTopicsWithMastery(for subject: String, weaknessTopics: [String]) -> [String] {
        let statusService = ShortTermStatusService.shared
        let weaknesses = statusService.status.activeWeaknesses

        // Find mastery topics (value < 0)
        let masteryTopics = weaknesses
            .filter { key, value in
                let components = key.split(separator: "/").map(String.init)
                guard let weaknessSubject = components.first else { return false }
                return weaknessSubject.lowercased() == subject.lowercased() && value.value < 0
            }
            .sorted { $0.value.value < $1.value.value }  // Most negative = strongest mastery

        print("🎯 [Adapter] Mixing topics for balanced practice:")
        print("   Weakness topics (80%): \(weaknessTopics)")

        // Extract base branches from mastery
        var masteryBranches: [String] = []
        for (key, weakness) in masteryTopics.prefix(2) {  // Top 2 mastery areas
            let components = key.split(separator: "/").map(String.init)
            if components.count >= 2 {
                let branch = components[1]
                masteryBranches.append(branch)
                print("   Mastery topic found: \(branch) (mastery: \(String(format: "%.2f", weakness.value)))")
            }
        }

        // Mix: 80% weakness + 20% mastery for confidence
        var mixed = weaknessTopics
        if !masteryBranches.isEmpty {
            mixed.append(masteryBranches.first!)
            print("   Mastery topics (20%): [\(masteryBranches.first!)]")
        }

        print("   ✅ Final mixed topics: \(mixed)")
        return mixed
    }
}