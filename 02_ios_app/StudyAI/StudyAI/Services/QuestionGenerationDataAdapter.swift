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
        let profileService = ProfileService.shared

        // Resolve grade to a human-readable string the AI can enforce (e.g. "1st Grade")
        // Child accounts may store grade as "1" (numeric string) — normalize it.
        let grade = resolvedGradeLabel(from: profileService.currentProfile?.gradeLevel)
        let location = profileService.currentProfile?.displayLocation ?? "US"

        var preferences: [String: Any] = [:]
        preferences["preferred_question_types"] = ["multiple_choice", "short_answer"]
        preferences["difficulty_preference"] = "adaptive"

        // In a child session, use the child's locally stored subjects and learning style
        // instead of the parent's server profile data.
        if UserDefaults.standard.bool(forKey: "isChildSessionActive"),
           let childId = AuthenticationService.shared.currentUser?.id {
            let childData = UserDefaults.standard.data(forKey: "child_local_\(childId)")
            let childLocal = childData.flatMap { try? JSONDecoder().decode(ChildLocalProfile.self, from: $0) }
            let childSubjects = childLocal?.subjects.isEmpty == false ? childLocal!.subjects : nil
            preferences["subject_interests"] = childSubjects ?? profileService.currentProfile?.favoriteSubjects ?? ["Mathematics"]
        } else {
            preferences["subject_interests"] = profileService.currentProfile?.favoriteSubjects ?? ["Mathematics"]
        }

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
        return ["Mathematics", "General"]
    }

    /// Get common subjects for selection.
    /// Returns English canonical names (used as API keys); UI localizes via BranchLocalizer.
    /// Dynamically appends any "Others: X" subjects the user has encountered in their history.
    func getMostCommonSubjects() -> [String] {
        let base: [String] = [
            "Mathematics", "Science", "Physics", "Chemistry", "Biology",
            "English", "History", "Geography", "Computer Science",
            "Literature", "Social Studies", "Economics", "Art", "Music"
        ]

        // Append unique "Others: X" subjects from the user's local question history
        let allQuestions = currentUserQuestionStorage().getLocalQuestions()
        var seen = Set<String>()
        var othersSubjects: [String] = []
        for q in allQuestions {
            if let s = q["subject"] as? String, s.hasPrefix("Others: "), !seen.contains(s) {
                seen.insert(s)
                othersSubjects.append(s)
            }
        }
        othersSubjects.sort()

        return base + othersSubjects + ["Other"]
    }

    // MARK: - Personalized Data from Short-Term Status

    /// Extract weakness topics for a specific subject from short-term status
    func getWeaknessTopics(for subject: String) -> [String] {
        let statusService = ShortTermStatusService.shared
        let weaknesses = statusService.status.activeWeaknesses

        debugPrint("🔍 [Adapter] Analyzing short-term status for subject: \(subject)")
        debugPrint("   Total active weaknesses: \(weaknesses.count)")

        // Filter by subject and extract base branches (prioritize high-value weaknesses)
        let subjectWeaknesses = weaknesses
            .filter { key, value in
                let components = key.split(separator: "/").map(String.init)
                guard let weaknessSubject = components.first else { return false }

                // Match subject and only include actual weaknesses (value > 0)
                return weaknessSubject.lowercased() == subject.lowercased() && value.value > 0
            }
            .sorted { $0.value.value > $1.value.value }  // Sort by weakness severity

        debugPrint("   Subject-specific weaknesses (value > 0): \(subjectWeaknesses.count)")

        // Extract unique base branches (main topic areas)
        var baseBranches: [String] = []
        for (key, weakness) in subjectWeaknesses.prefix(10) {  // Top 10 weaknesses
            let components = key.split(separator: "/").map(String.init)
            if components.count >= 2 {
                let baseBranch = components[1]
                if !baseBranches.contains(baseBranch) {
                    baseBranches.append(baseBranch)
                    debugPrint("      - \(baseBranch) (severity: \(String(format: "%.2f", weakness.value)))")
                }
            }
        }

        // If no weaknesses found, return general subject
        let result = baseBranches.isEmpty ? [subject] : baseBranches
        debugPrint("   ✅ Extracted weakness topics: \(result)")
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

        debugPrint("📝 [Adapter] Generated personalized focus notes:")
        debugPrint(notes)

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
            debugPrint("📊 [Adapter] No performance data - using intermediate difficulty")
            return .intermediate  // Default
        }

        let totalAttempts = subjectWeaknesses.values.reduce(0) { $0 + $1.totalAttempts }
        let totalCorrect = subjectWeaknesses.values.reduce(0) { $0 + $1.correctAttempts }

        guard totalAttempts > 0 else {
            debugPrint("📊 [Adapter] No attempts recorded - using intermediate difficulty")
            return .intermediate
        }

        let accuracy = Double(totalCorrect) / Double(totalAttempts)

        debugPrint("📊 [Adapter] Performance analysis:")
        debugPrint("   Total attempts: \(totalAttempts)")
        debugPrint("   Correct: \(totalCorrect)")
        debugPrint("   Accuracy: \(String(format: "%.1f%%", accuracy * 100))")

        // Adaptive difficulty based on accuracy
        let difficulty: QuestionGenerationService.RandomQuestionsConfig.QuestionDifficulty
        if accuracy < 0.5 {
            difficulty = .beginner  // Struggling - make it easier
            debugPrint("   → Recommendation: BEGINNER (struggling)")
        } else if accuracy < 0.75 {
            difficulty = .intermediate  // Still learning
            debugPrint("   → Recommendation: INTERMEDIATE (learning)")
        } else {
            difficulty = .advanced  // Strong performance - challenge them
            debugPrint("   → Recommendation: ADVANCED (strong)")
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

        debugPrint("🎯 [Adapter] Mixing topics for balanced practice:")
        debugPrint("   Weakness topics (80%): \(weaknessTopics)")

        // Extract base branches from mastery
        var masteryBranches: [String] = []
        for (key, weakness) in masteryTopics.prefix(2) {  // Top 2 mastery areas
            let components = key.split(separator: "/").map(String.init)
            if components.count >= 2 {
                let branch = components[1]
                masteryBranches.append(branch)
                debugPrint("   Mastery topic found: \(branch) (mastery: \(String(format: "%.2f", weakness.value)))")
            }
        }

        // Mix: 80% weakness + 20% mastery for confidence
        var mixed = weaknessTopics
        if !masteryBranches.isEmpty {
            mixed.append(masteryBranches.first!)
            debugPrint("   Mastery topics (20%): [\(masteryBranches.first!)]")
        }

        debugPrint("   ✅ Final mixed topics: \(mixed)")
        return mixed
    }

    // MARK: - Grade Helpers

    /// Converts stored gradeLevel string (may be "1", "1st Grade", or nil) to
    /// the canonical label the AI engine understands (e.g. "1st Grade", "Kindergarten").
    func resolvedGradeLabel(from gradeString: String?) -> String {
        guard let raw = gradeString, !raw.isEmpty else { return "High School" }

        // Already a recognised GradeLevel rawValue — e.g. "6th Grade"
        if GradeLevel(rawValue: raw) != nil { return raw }

        // Numeric string stored by FamilyService — e.g. "1", "6"
        if let n = Int(raw.trimmingCharacters(in: .whitespaces)),
           let level = GradeLevel.allCases.first(where: { $0.numericValue == n }) {
            return level.rawValue   // returns "1st Grade", "2nd Grade", etc.
        }

        // Fallback — return as-is and let the backend handle it
        return raw
    }
}