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

    private let questionLocalStorage = QuestionLocalStorage.shared

    /// Fetch subjects with mistake counts from LOCAL STORAGE ONLY
    func fetchSubjectsWithMistakes(timeRange: MistakeTimeRange? = nil) async {
        #if DEBUG
        print("🔍 [MistakeReview] === FETCHING SUBJECTS FROM LOCAL STORAGE ===")
        print("🔍 [MistakeReview] Time range: \(timeRange?.rawValue ?? "All Time")")
        #endif

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

        #if DEBUG
        print("✅ [MistakeReview] Successfully fetched subjects from local storage")
        print("📊 [MistakeReview] Found \(subjects.count) subjects with mistakes in time range:")
        for subject in subjects {
            print("   - \(subject.subject): \(subject.mistakeCount) mistakes")
        }
        #endif

        self.subjectsWithMistakes = subjects
        isLoading = false

        #if DEBUG
        print("🔍 [MistakeReview] === FETCH SUBJECTS COMPLETE ===\n")
        #endif
    }

    /// Fetch mistakes from LOCAL STORAGE ONLY
    func fetchMistakes(subject: String?, timeRange: MistakeTimeRange) async {
        #if DEBUG
        print("🔍 [MistakeReview] === FETCHING MISTAKES FROM LOCAL STORAGE ===")
        print("🔍 [MistakeReview] Subject: \(subject ?? "All Subjects")")
        print("🔍 [MistakeReview] Time range: \(timeRange.rawValue)")
        #endif

        isLoading = true
        errorMessage = nil

        // ✅ Fetch from local storage only
        let allMistakeData = questionLocalStorage.getMistakeQuestions(subject: subject)

        #if DEBUG
        print("🔍 [MistakeReviewService] Fetched \(allMistakeData.count) mistakes from local storage")
        // Log first few with image URLs
        for (index, data) in allMistakeData.prefix(3).enumerated() {
            if let imageUrl = data["questionImageUrl"] as? String, !imageUrl.isEmpty {
                print("   📸 Mistake \(index + 1) has image: \(imageUrl)")
            }
        }
        #endif

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

                #if DEBUG
                if questionImageUrl != nil {
                    print("   🔍 [MistakeReviewService] Created MistakeQuestion with image:")
                    print("      - id: \(id)")
                    print("      - questionImageUrl: '\(questionImageUrl ?? "nil")'")
                    print("      - rawQuestionText: \(rawQuestionText.prefix(50))...")
                }
                #endif

                mistakes.append(mistake)
            }
        }

        #if DEBUG
        print("✅ [MistakeReview] Successfully fetched mistakes from local storage")
        print("📊 [MistakeReview] Total mistakes retrieved: \(mistakes.count)")

        if mistakes.isEmpty {
            print("⚠️ [MistakeReview] No mistakes found in local storage")
        } else {
            print("📋 [MistakeReview] Mistake summary:")
            for (index, mistake) in mistakes.prefix(5).enumerated() {
                // ⚠️ SECURITY: Only log first 30 chars of potentially sensitive data
                print("   \(index + 1). [\(mistake.subject)] \(mistake.question.prefix(30))...")
            }
            if mistakes.count > 5 {
                print("   ... and \(mistakes.count - 5) more")
            }
        }
        #endif

        self.mistakes = mistakes
        isLoading = false

        #if DEBUG
        print("🔍 [MistakeReview] === FETCH MISTAKES COMPLETE ===\n")
        #endif
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
    func filterByTimeRange(_ mistakes: [[String: Any]], timeRange: MistakeTimeRange?) -> [[String: Any]] {
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
            #if DEBUG
            if parsedDatesCount + failedParseCount < 5 {
                print("🔍 [MistakeReview] Checking mistake: subject=\(mistake["subject"] as? String ?? "N/A"), archivedAt=\(mistake["archivedAt"] as? String ?? "MISSING")")
            }
            #endif

            guard let archivedAtString = mistake["archivedAt"] as? String else {
                failedParseCount += 1
                #if DEBUG
                if failedParseCount <= 3 {
                    print("⚠️ [MistakeReview] Missing archivedAt field in mistake")
                }
                #endif
                return false
            }

            // ✅ Use cached date parsing for performance
            guard let mistakeDate = QuestionLocalStorage.shared.getDateCached(archivedAtString) else {
                failedParseCount += 1
                #if DEBUG
                if failedParseCount <= 3 {
                    print("⚠️ [MistakeReview] Failed to parse date: \(archivedAtString)")
                }
                #endif
                return false
            }

            parsedDatesCount += 1
            let matches = mistakeDate >= cutoffDate
            if matches {
                matchingCount += 1
            }

            // Log first few comparisons
            #if DEBUG
            if parsedDatesCount <= 5 {
                print("🔍 [MistakeReview] Mistake date: \(mistakeDate), matches: \(matches)")
            }
            #endif

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

    // MARK: - Hierarchical Filtering Support

    /// Get base branches with counts for a subject
    func getBaseBranches(for subject: String, timeRange: MistakeTimeRange?, activeFilter: MistakeActiveFilter = .all) -> [BaseBranchCount] {
        let allMistakes = questionLocalStorage.getMistakeQuestions(subject: subject)
        var filteredMistakes = filterByTimeRange(allMistakes, timeRange: timeRange)

        // Apply active weakness filter if needed
        if activeFilter == .active {
            let activeWeaknesses = ShortTermStatusService.shared.status.activeWeaknesses
            filteredMistakes = filteredMistakes.filter { mistake in
                guard let key = mistake["weaknessKey"] as? String, !key.isEmpty else {
                    return true // no key → include
                }
                return (activeWeaknesses[key]?.value ?? 0) > 0
            }
        }

        // ✅ DEBUG: Inspect what's actually stored in the first few mistakes
        print("\n🔍 [DEBUG] getBaseBranches called for subject: \(subject)")
        print("   Total mistakes after time filter: \(filteredMistakes.count)")

        for (index, mistake) in filteredMistakes.prefix(5).enumerated() {
            let baseBranch = mistake["baseBranch"] as? String
            let detailedBranch = mistake["detailedBranch"] as? String
            let weaknessKey = mistake["weaknessKey"] as? String
            let subject = mistake["subject"] as? String
            let questionPreview = (mistake["questionText"] as? String)?.prefix(40) ?? "N/A"
            let errorAnalysisStatus = mistake["errorAnalysisStatus"] as? String
            let archivedAt = mistake["archivedAt"] as? String

            print("\n   📋 Mistake #\(index + 1):")
            print("      Subject: '\(subject ?? "NIL")'")
            print("      baseBranch: '\(baseBranch ?? "NIL")'")
            print("      detailedBranch: '\(detailedBranch ?? "NIL")'")
            print("      weaknessKey: '\(weaknessKey ?? "NIL")'")
            print("      errorAnalysisStatus: '\(errorAnalysisStatus ?? "NIL")'")
            print("      archivedAt: '\(archivedAt ?? "NIL")'")
            print("      Question: '\(questionPreview)...'")
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

        print("\n   ✅ Grouped into \(branchGroups.count) base branches (\(uncategorizedCount) uncategorized)")
        for (branch, mistakes) in branchGroups.sorted(by: { $0.value.count > $1.value.count }) {
            print("      - \(branch): \(mistakes.count) mistakes")
        }
        print("")

        // Convert to BaseBranchCount with detailed branches
        return branchGroups.map { baseBranch, mistakes in
            let detailedBranches = getDetailedBranchesInternal(from: mistakes)
            return BaseBranchCount(
                baseBranch: baseBranch,
                mistakeCount: mistakes.count,
                detailedBranches: detailedBranches
            )
        }.sorted {
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