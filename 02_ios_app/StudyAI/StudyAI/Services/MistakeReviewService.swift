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
    /// Sentinel key used to bucket questions whose baseBranch/detailedBranch is nil or empty.
    static let uncategorizedKey = "__uncategorized__"

    @Published var isLoading = false
    @Published var subjectsWithMistakes: [SubjectMistakeCount] = []
    @Published var mistakes: [MistakeQuestion] = []
    @Published var errorMessage: String?

    private var questionLocalStorage: QuestionLocalStorage { currentUserQuestionStorage() }

    /// Fetch subjects with mistake counts from LOCAL STORAGE ONLY
    func fetchSubjectsWithMistakes(timeRange: MistakeTimeRange? = nil) async {
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

        self.subjectsWithMistakes = subjects
        isLoading = false
    }

    /// Fetch mistakes from LOCAL STORAGE ONLY
    func fetchMistakes(subject: String?, timeRange: MistakeTimeRange) async {
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

                // ✅ Extract error analysis fields (eliminates double fetch!)
                let errorType = data["errorType"] as? String
                let errorEvidence = data["errorEvidence"] as? String
                let errorConfidence = (data["errorConfidence"] as? Double) ?? (data["errorConfidence"] as? Float).map(Double.init)
                let learningSuggestion = data["learningSuggestion"] as? String

                // ✅ Convert string status to enum with backwards compatibility
                // For old mistakes without analysis status, mark as failed (no analysis available)
                // Only new mistakes from grading will have pending/processing status
                let statusString = data["errorAnalysisStatus"] as? String ?? "failed"
                let errorAnalysisStatus = ErrorAnalysisStatus(rawValue: statusString) ?? .failed

                // ✅ Extract hierarchical taxonomy fields
                let baseBranch = data["baseBranch"] as? String
                let detailedBranch = data["detailedBranch"] as? String
                let specificIssue = data["specificIssue"] as? String
                let weaknessKey = data["weaknessKey"] as? String

                // ✅ Extract Pro Mode image field
                let questionImageUrl = data["questionImageUrl"] as? String

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
                    notes: notes,
                    errorType: errorType,
                    errorEvidence: errorEvidence,
                    errorConfidence: errorConfidence,
                    learningSuggestion: learningSuggestion,
                    errorAnalysisStatus: errorAnalysisStatus,
                    weaknessKey: weaknessKey,
                    baseBranch: baseBranch,
                    detailedBranch: detailedBranch,
                    specificIssue: specificIssue,
                    questionImageUrl: questionImageUrl
                )

                mistakes.append(mistake)
            }
        }

        self.mistakes = mistakes
        isLoading = false
    }

    /// Get mistake statistics from LOCAL STORAGE ONLY
    func getMistakeStats() async -> MistakeStats? {
        let allMistakes = questionLocalStorage.getMistakeQuestions()
        let subjectData = questionLocalStorage.getSubjectsWithMistakes()

        let mistakesLastWeek = filterByTimeRange(allMistakes, timeRange: .thisWeek).count
        let mistakesLastMonth = filterByTimeRange(allMistakes, timeRange: .thisMonth).count

        return MistakeStats(
            totalMistakes: allMistakes.count,
            subjectsWithMistakes: subjectData.count,
            mistakesLastWeek: mistakesLastWeek,
            mistakesLastMonth: mistakesLastMonth
        )
    }

    /// Filter mistakes by time range
    func filterByTimeRange(_ mistakes: [[String: Any]], timeRange: MistakeTimeRange?) -> [[String: Any]] {
        guard let timeRange = timeRange else {
            return mistakes
        }

        let now = Date()
        let calendar = Calendar.current

        let cutoffDate: Date
        switch timeRange {
        case .thisWeek:
            cutoffDate = calendar.date(byAdding: .day, value: -7, to: now)!
        case .thisMonth:
            cutoffDate = calendar.date(byAdding: .day, value: -30, to: now)!
        case .allTime:
            return mistakes
        }

        let filtered = mistakes.filter { mistake in
            guard let archivedAtString = mistake["archivedAt"] as? String else {
                return false
            }

            guard let mistakeDate = currentUserQuestionStorage().getDateCached(archivedAtString) else {
                return false
            }

            return mistakeDate >= cutoffDate
        }

        return filtered
    }

    /// Get icon for subject (uses SF Symbols compatible with Image(systemName:))
    private func getSubjectIcon(_ subject: String) -> String {
        if subject.hasPrefix("Others:") { return "folder.fill" }
        return Subject.normalizeWithFallback(subject).icon
    }

    // MARK: - Hierarchical Filtering Support

    /// Get base branches with counts for a subject
    func getBaseBranches(for subject: String, timeRange: MistakeTimeRange?, activeFilter: MistakeActiveFilter = .all, severity: SeverityLevel = .all) -> [BaseBranchCount] {
        let allMistakes = questionLocalStorage.getMistakeQuestions(subject: subject)
        var filteredMistakes = filterByTimeRange(allMistakes, timeRange: timeRange)

        // Apply active weakness filter if needed
        if activeFilter == .active {
            let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses
            filteredMistakes = filteredMistakes.filter { mistake in
                guard let key = mistake["weaknessKey"] as? String, !key.isEmpty else {
                    return true // no weakness key → include (old/untracked questions)
                }
                return ShortTermStatusService.shared.isActiveWeakness(key)
            }
        }

        // Apply severity filter
        if severity != .all {
            filteredMistakes = filteredMistakes.filter { severity.matches(errorType: $0["errorType"] as? String) }
        }

        // Group by base branch (questions with no baseBranch go into the uncategorized bucket)
        var branchGroups: [String: [[String: Any]]] = [:]
        var uncategorizedCount = 0

        for mistake in filteredMistakes {
            let baseBranch = (mistake["baseBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if let branch = baseBranch {
                branchGroups[branch, default: []].append(mistake)
            } else {
                branchGroups[MistakeReviewService.uncategorizedKey, default: []].append(mistake)
                uncategorizedCount += 1
            }
        }

        // Convert to BaseBranchCount with detailed branches
        return branchGroups.map { baseBranch, mistakes in
            let detailedBranches = getDetailedBranchesInternal(from: mistakes)
            return BaseBranchCount(
                baseBranch: baseBranch,
                mistakeCount: mistakes.count,
                detailedBranches: detailedBranches
            )
        }.filter { $0.mistakeCount > 0 }.sorted {
            // Uncategorized always goes last
            if $0.baseBranch == MistakeReviewService.uncategorizedKey { return false }
            if $1.baseBranch == MistakeReviewService.uncategorizedKey { return true }
            // Primary sort: by mistake count (descending)
            if $0.mistakeCount != $1.mistakeCount {
                return $0.mistakeCount > $1.mistakeCount
            }
            // Secondary sort: alphabetically by base branch name
            return $0.baseBranch < $1.baseBranch
        }
    }

    /// Get detailed branches with counts for a base branch
    func getDetailedBranches(for subject: String, baseBranch: String, timeRange: MistakeTimeRange?) -> [DetailedBranchCount] {
        let allMistakes = questionLocalStorage.getMistakeQuestions(subject: subject)
        let filteredMistakes = filterByTimeRange(allMistakes, timeRange: timeRange)

        // Filter by base branch
        let branchMistakes = filteredMistakes.filter { mistake in
            (mistake["baseBranch"] as? String) == baseBranch
        }

        return getDetailedBranchesInternal(from: branchMistakes)
    }

    /// Get branches where the user has answered correctly, with per-branch accuracy.
    /// Uses ShortTermStatusService.activeWeaknesses as source — keys are "Subject/baseBranch/detailedBranch"
    /// and correctAttempts is populated for all correct answers (not just mistakes).
    func getGoodAtBranches(for subject: String, timeRange: MistakeTimeRange?) -> [GoodAtBranchCount] {
        let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses
        let prefix = "\(subject)/"

        // Only entries for this subject with at least one correct attempt
        let subjectEntries = activeWeaknesses.filter { key, value in
            key.hasPrefix(prefix) && value.correctAttempts > 0
        }

        // Aggregate by baseBranch → detailedBranch
        struct Counts { var total: Int; var correct: Int; var hadMistake: Bool }
        var baseBranchGroups: [String: [String: Counts]] = [:]

        for (key, value) in subjectEntries {
            let components = key.split(separator: "/", maxSplits: 2)
            guard components.count >= 2 else { continue }
            let baseBranch = String(components[1])
            let detailedBranch = components.count >= 3 ? String(components[2]) : MistakeReviewService.uncategorizedKey

            // A key was ever a weakness if the user made at least one mistake on it
            let hadMistake = (value.totalAttempts - value.correctAttempts) > 0
            let existing = baseBranchGroups[baseBranch]?[detailedBranch] ?? Counts(total: 0, correct: 0, hadMistake: false)
            baseBranchGroups[baseBranch, default: [:]][detailedBranch] = Counts(
                total: existing.total + value.totalAttempts,
                correct: existing.correct + value.correctAttempts,
                hadMistake: existing.hadMistake || hadMistake
            )
        }

        return baseBranchGroups.compactMap { baseBranch, detailGroups -> GoodAtBranchCount? in
            let totalCount = detailGroups.values.reduce(0) { $0 + $1.total }
            let correctCount = detailGroups.values.reduce(0) { $0 + $1.correct }
            let overallAccuracy = totalCount > 0 ? Double(correctCount) / Double(totalCount) : 0.0
            // Only show in "掌握" if accuracy is currently ≥ 50%
            guard correctCount > 0, overallAccuracy >= 0.5 else { return nil }

            let detailedBranches = detailGroups.compactMap { detail, counts -> GoodAtDetailedBranchCount? in
                let detailAccuracy = counts.total > 0 ? Double(counts.correct) / Double(counts.total) : 0.0
                guard counts.correct > 0, detailAccuracy >= 0.5 else { return nil }
                return GoodAtDetailedBranchCount(
                    detailedBranch: detail,
                    totalCount: counts.total,
                    correctCount: counts.correct,
                    wasWeakness: counts.hadMistake
                )
            }.sorted {
                if $0.accuracy != $1.accuracy { return $0.accuracy > $1.accuracy }
                return $0.totalCount > $1.totalCount
            }

            return GoodAtBranchCount(
                baseBranch: baseBranch,
                totalCount: totalCount,
                correctCount: correctCount,
                detailedBranches: detailedBranches
            )
        }.sorted {
            if $0.accuracy != $1.accuracy { return $0.accuracy > $1.accuracy }
            return $0.totalCount > $1.totalCount
        }
    }

    /// Internal helper to group mistakes by detailed branch
    private func getDetailedBranchesInternal(from mistakes: [[String: Any]]) -> [DetailedBranchCount] {
        var branchCounts: [String: Int] = [:]
        for mistake in mistakes {
            let detailedBranch = (mistake["detailedBranch"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let key = detailedBranch ?? MistakeReviewService.uncategorizedKey
            branchCounts[key, default: 0] += 1
        }

        return branchCounts.map { branch, count in
            DetailedBranchCount(detailedBranch: branch, mistakeCount: count)
        }.sorted {
            // Uncategorized always goes last
            if $0.detailedBranch == MistakeReviewService.uncategorizedKey { return false }
            if $1.detailedBranch == MistakeReviewService.uncategorizedKey { return true }
            // Primary sort: by mistake count (descending)
            if $0.mistakeCount != $1.mistakeCount {
                return $0.mistakeCount > $1.mistakeCount
            }
            // Secondary sort: alphabetically by detailed branch name
            return $0.detailedBranch < $1.detailedBranch
        }
    }

    /// Get error type counts with optional filters
    func getErrorTypeCounts(for subject: String, baseBranch: String?, detailedBranch: String?, timeRange: MistakeTimeRange?) -> [ErrorTypeCount] {
        let allMistakes = questionLocalStorage.getMistakeQuestions(subject: subject)
        var filteredMistakes = filterByTimeRange(allMistakes, timeRange: timeRange)

        // Filter by base branch if provided
        if let baseBranch = baseBranch {
            filteredMistakes = filteredMistakes.filter { mistake in
                (mistake["baseBranch"] as? String) == baseBranch
            }
        }

        // Filter by detailed branch if provided
        if let detailedBranch = detailedBranch {
            filteredMistakes = filteredMistakes.filter { mistake in
                (mistake["detailedBranch"] as? String) == detailedBranch
            }
        }

        // Group by error type
        var typeCounts: [String: Int] = [:]
        for mistake in filteredMistakes {
            guard let errorType = mistake["errorType"] as? String, !errorType.isEmpty else {
                continue
            }
            typeCounts[errorType, default: 0] += 1
        }

        // Convert to ErrorTypeCount with colors
        return typeCounts.map { errorType, count in
            ErrorTypeCount(
                errorType: errorType,
                mistakeCount: count,
                color: colorForErrorType(errorType)
            )
        }.sorted { $0.mistakeCount > $1.mistakeCount }
    }

    /// Get color for error type
    private func colorForErrorType(_ errorType: String) -> Color {
        switch errorType {
        case "execution_error": return .yellow
        case "conceptual_gap": return .red
        case "needs_refinement": return .blue
        default: return .gray
        }
    }

    // MARK: - Branch Accuracy (for Weak Point Heatmap)

    /// Top `limit` base branches for a subject ranked by weakness value (highest = most weak).
    /// Reads ShortTermStatusService.activeWeaknesses and aggregates by key component[1].
    func getBaseBranchAccuracy(for subject: String, limit: Int = 3) -> [BranchAccuracyData] {
        let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses

        struct Agg { var total = 0; var correct = 0; var valueSum = 0.0; var count = 0 }
        var groups: [String: Agg] = [:]

        for (key, val) in activeWeaknesses {
            let parts = key.split(separator: "/", maxSplits: 2)
            guard parts.count >= 2, String(parts[0]) == subject else { continue }
            let normBase = String(parts[1])   // already lowercased+underscored
            var g = groups[normBase] ?? Agg()
            g.total += val.totalAttempts
            g.correct += val.correctAttempts
            g.valueSum += val.value
            g.count += 1
            groups[normBase] = g
        }

        return groups
            .filter { $0.value.total > 0 }
            .map { normBase, g in
                BranchAccuracyData(
                    name: normBase
                        .replacingOccurrences(of: "_", with: " ")
                        .split(separator: " ")
                        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                        .joined(separator: " "),
                    totalAttempts: g.total,
                    correctAttempts: g.correct,
                    weaknessValue: g.count > 0 ? g.valueSum / Double(g.count) : 0
                )
            }
            .sorted { $0.weaknessValue > $1.weaknessValue }
            .prefix(limit)
            .map { $0 }
    }

    /// Top `limit` detailed branches under a given base branch, ranked by weakness value.
    /// `baseBranch` is the humanized display name (e.g. "Algebra - Advanced") — normalized internally.
    func getDetailedBranchAccuracy(for subject: String, baseBranch: String, limit: Int = 3) -> [BranchAccuracyData] {
        let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses

        struct Agg { var total = 0; var correct = 0; var valueSum = 0.0; var count = 0 }
        var groups: [String: Agg] = [:]

        for (key, val) in activeWeaknesses {
            let parts = key.split(separator: "/", maxSplits: 2)
            guard parts.count >= 3,
                  String(parts[0]) == subject else { continue }

            // Humanize the stored key part the same way getBaseBranchAccuracy builds display names,
            // so the comparison works regardless of whether the stored value uses spaces, dashes,
            // underscores, or mixed case.
            let storedDisplayName = String(parts[1])
                .replacingOccurrences(of: "_", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")

            guard storedDisplayName == baseBranch else { continue }
            let detail = String(parts[2])
            var g = groups[detail] ?? Agg()
            g.total += val.totalAttempts
            g.correct += val.correctAttempts
            g.valueSum += val.value
            g.count += 1
            groups[detail] = g
        }

        return groups
            .filter { $0.value.total > 0 }
            .map { detail, g in
                BranchAccuracyData(
                    name: detail
                        .replacingOccurrences(of: "_", with: " ")
                        .split(separator: " ")
                        .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                        .joined(separator: " "),
                    totalAttempts: g.total,
                    correctAttempts: g.correct,
                    weaknessValue: g.count > 0 ? g.valueSum / Double(g.count) : 0
                )
            }
            .sorted { $0.weaknessValue > $1.weaknessValue }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Hierarchical Data Structures

struct BaseBranchCount: Identifiable {
    let id = UUID()
    let baseBranch: String
    let mistakeCount: Int
    let detailedBranches: [DetailedBranchCount]
}

struct DetailedBranchCount: Identifiable {
    let id = UUID()
    let detailedBranch: String
    let mistakeCount: Int
}

// MARK: - Good At Data Structures

struct GoodAtBranchCount: Identifiable {
    let id = UUID()
    let baseBranch: String
    let totalCount: Int
    let correctCount: Int
    let detailedBranches: [GoodAtDetailedBranchCount]

    var accuracy: Double {
        totalCount > 0 ? Double(correctCount) / Double(totalCount) : 0
    }

    /// True if any detailed branch under this base branch was once a weakness.
    /// Used to split the "Good At" section into "Your Strengths" vs "No Longer a Weakness".
    var wasWeakness: Bool {
        detailedBranches.contains { $0.wasWeakness }
    }
}

struct GoodAtDetailedBranchCount: Identifiable {
    let id = UUID()
    let detailedBranch: String
    let totalCount: Int
    let correctCount: Int
    /// True when the user made at least one mistake on this branch before mastering it.
    let wasWeakness: Bool

    var accuracy: Double {
        totalCount > 0 ? Double(correctCount) / Double(totalCount) : 0
    }
}

struct ErrorTypeCount: Identifiable {
    let id = UUID()
    let errorType: String
    let mistakeCount: Int
    let color: Color

    var displayName: String {
        switch errorType {
        case "execution_error": return "Execution Error"
        case "conceptual_gap": return "Concept Gap"
        case "needs_refinement": return "Needs Refinement"
        default: return errorType
        }
    }

    var icon: String {
        switch errorType {
        case "execution_error": return "exclamationmark.circle"
        case "conceptual_gap": return "brain.head.profile"
        case "needs_refinement": return "star.circle"
        default: return "questionmark.circle"
        }
    }
}

// MARK: - Branch Accuracy (for Weak Point Heatmap)

struct BranchAccuracyData: Identifiable {
    let id = UUID()
    let name: String           // humanized display name
    let totalAttempts: Int
    let correctAttempts: Int
    let weaknessValue: Double  // average .value across all keys in this branch; ≤0 = mastered

    var accuracy: Double {
        totalAttempts > 0 ? Double(correctAttempts) / Double(totalAttempts) : 0.0
    }

    var isMastered: Bool { weaknessValue <= 0 }

    var heatColor: Color {
        if isMastered { return .green }
        if accuracy >= 0.75 { return Color(hue: 0.28, saturation: 0.7, brightness: 0.65) }
        if accuracy >= 0.55 { return .yellow }
        if accuracy >= 0.35 { return .orange }
        return .red
    }
}