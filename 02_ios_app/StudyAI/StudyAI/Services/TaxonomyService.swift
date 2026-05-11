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

    /// Returns all subjects that have a taxonomy JSON for the current user's grade.
    func availableSubjects() -> [SubjectMistakeCount] {
        let candidates: [(name: String, icon: String)] = [
            ("Mathematics",  "function"),
            ("English",      "textformat.abc"),
            ("Science",      "atom"),
            ("General",      "graduationcap.fill")
        ]
        return candidates.compactMap { entry in
            guard TaxonomyService.taxonomyFilename(for: entry.name) != nil else { return nil }
            return SubjectMistakeCount(subject: entry.name, mistakeCount: 0, icon: entry.icon)
        }
    }

    /// Subject name → JSON filename mapping
    static func taxonomyFilename(for subject: String) -> String? {
        let lower = subject.lowercased()
        if lower.contains("math") || lower.contains("数学")   { return "math_taxonomy" }
        if lower.contains("english") || lower.contains("英语") { return "english_taxonomy" }
        if lower.contains("science") || lower.contains("物理") ||
           lower.contains("化学") || lower.contains("生物")    { return "science_taxonomy" }
        if lower.contains("general") || lower.contains("综合")  { return "general_taxonomy" }
        return nil
    }

    // MARK: - Helpers

    private func currentGrade() -> Int {
        guard let gradeString = ProfileService.shared.currentProfile?.gradeLevel,
              let level = GradeLevel(rawValue: gradeString) else { return 6 }  // default grade 6
        return level.numericValue
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
