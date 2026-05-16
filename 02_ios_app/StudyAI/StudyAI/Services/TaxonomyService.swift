import Foundation
import SwiftUI

/// Loads bundled subject taxonomy JSON files, filters by the current user's grade,
/// then overlays practice data from ShortTermStatusService + QuestionLocalStorage.
final class TaxonomyService {

    static let shared = TaxonomyService()

    // MARK: - Public API

    /// Returns KnowledgeTreeBranch array for the given subject, filtered to the user's grade.
    /// Each topic's `weaknessValue` and `questionCount` are populated from local practice data.
    func knowledgeTree(for subject: String) -> [KnowledgeTreeBranch] {
        let grade = currentGrade()
        let raw = loadTaxonomy(subject: subject)
        let weaknesses = ShortTermStatusService.shared.status.activeWeaknesses
        let storage = currentUserQuestionStorage()

        return raw.branches.compactMap { branch in
            let filteredTopics = branch.topics
                .filter { $0.gradeMin <= grade && grade <= $0.gradeMax }
                .map { topic -> KnowledgeTreeTopic in
                    let key = "\(subject)/\(branch.name)/\(topic.name)"
                    let wv = weaknesses[key]
                    let count = questionCount(for: key, storage: storage)
                    return KnowledgeTreeTopic(
                        id: topic.id,
                        topicName: topic.name,
                        branchName: branch.name,
                        gradeRange: topic.gradeMin...topic.gradeMax,
                        weaknessValue: wv,
                        questionCount: count
                    )
                }
            guard !filteredTopics.isEmpty else { return nil }
            return KnowledgeTreeBranch(id: branch.id, name: branch.name, topics: filteredTopics)
        }
    }

    /// Returns subjects that have at least one grade-appropriate topic for the current user.
    func availableSubjects() -> [SubjectMistakeCount] {
        let grade = currentGrade()
        let candidates: [(name: String, icon: String)] = [
            ("Math",             "function"),
            ("English",          "textformat.abc"),
            ("Science",          "atom"),
            ("Biology",          "leaf.fill"),
            ("Chemistry",        "flame.fill"),
            ("Physics",          "bolt.fill"),
            ("History",          "book.closed.fill"),
            ("Geography",        "globe.americas.fill"),
            ("Computer Science", "desktopcomputer"),
            ("Chinese",          "character.book.closed.fill"),
            ("Spanish",          "globe.europe.africa.fill"),
            ("General",          "graduationcap.fill")
        ]
        return candidates.compactMap { entry in
            guard TaxonomyService.taxonomyFilename(for: entry.name) != nil else { return nil }
            // Only include subjects that have at least one topic for this grade
            let raw = loadTaxonomy(subject: entry.name)
            let hasContent = raw.branches.contains { branch in
                branch.topics.contains { $0.gradeMin <= grade && grade <= $0.gradeMax }
            }
            guard hasContent else { return nil }
            return SubjectMistakeCount(subject: entry.name, mistakeCount: 0, icon: entry.icon)
        }
    }

    /// Subject name → JSON filename mapping
    static func taxonomyFilename(for subject: String) -> String? {
        let lower = subject.lowercased()
        if lower.contains("math")                                                          { return "math_taxonomy" }
        if lower.contains("english") || lower.contains("ela") || lower.contains("英语")   { return "english_taxonomy" }
        if lower.contains("physics") || lower.contains("物理")                             { return "physics_taxonomy" }
        if lower.contains("chemistry") || lower.contains("chem") || lower.contains("化学") { return "chemistry_taxonomy" }
        if lower.contains("biology") || lower.contains("bio") || lower.contains("生物")    { return "biology_taxonomy" }
        if lower.contains("history") || lower.contains("历史")                             { return "history_taxonomy" }
        if lower.contains("geography") || lower.contains("geo") || lower.contains("地理")  { return "geography_taxonomy" }
        if lower.contains("computer") || lower.contains("coding") || lower.contains("cs") { return "compsci_taxonomy" }
        if lower.contains("chinese") || lower.contains("语文") || lower.contains("中文")   { return "chinese_taxonomy" }
        if lower.contains("spanish") || lower.contains("español")                         { return "spanish_taxonomy" }
        if lower.contains("science") || lower.contains("科学")                             { return "science_taxonomy" }
        if lower.contains("general") || lower.contains("综合")                             { return "general_taxonomy" }
        return nil
    }

    // MARK: - Helpers

    private func currentGrade() -> Int {
        guard let gradeString = ProfileService.shared.currentProfile?.gradeLevel else { return 6 }

        // Format 1: matches GradeLevel rawValue exactly — e.g. "6th Grade"
        if let level = GradeLevel(rawValue: gradeString) {
            return level.numericValue
        }

        // Format 2: child accounts store grade as a numeric string — e.g. "6" or "1"
        if let n = Int(gradeString.trimmingCharacters(in: .whitespaces)),
           let level = GradeLevel.allCases.first(where: { $0.numericValue == n }) {
            return level.numericValue
        }

        // Format 3: FamilyService may also pass the display label — e.g. "Grade 6" or "6th"
        let lower = gradeString.lowercased()
        if let level = GradeLevel.allCases.first(where: {
            lower.contains($0.displayName.lowercased()) || lower == "\($0.numericValue)"
        }) {
            return level.numericValue
        }

        return 6  // safe default
    }

    private func loadTaxonomy(subject: String) -> SubjectTaxonomyJSON {
        guard let filename = TaxonomyService.taxonomyFilename(for: subject),
              let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(SubjectTaxonomyJSON.self, from: data)
        else {
            return SubjectTaxonomyJSON(subject: subject, branches: [])
        }
        return parsed
    }

    /// Count how many unique questions have been attempted for a given weakness key.
    private func questionCount(for key: String, storage: QuestionLocalStorage) -> Int {
        // Look up in activeWeaknesses for attempt count
        let wv = ShortTermStatusService.shared.status.activeWeaknesses[key]
        return wv?.totalAttempts ?? 0
    }
}
